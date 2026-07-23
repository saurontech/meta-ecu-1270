#!/usr/bin/env bash
#
# j722s-ecu1270_flash.sh — flash an SD/eMMC card for the
# Advantech ECU-1270 (TI J722S). Supports a plain non-RAUC single-rootfs
# layout (default) and a RAUC A/B layout (--rauc).
#
# Target board: TI J722S (ecu1270). The script creates a FAT16 boot partition
# (p1) for the TI K3 three-stage bootloader chain, then creates ext4 rootfs
# partition(s) and optionally a trailing ext4 partition for the overlayfs
# upper/work dirs.
#
# TI K3 boot chain (three separate files on the FAT boot partition — NOT a
# single raw-offset blob like i.MX imx-boot):
#   tiboot3.bin  — R5 first-stage (DMSC + System Firmware; HS-FS or HS-SE)
#   tispl.bin    — A53 SPL (TF-A + OP-TEE + DDR init)
#   u-boot.img   — U-Boot proper
# U-Boot env is stored as uboot.env on the same FAT partition (written by
# U-Boot on first boot; no pre-created file needed).
#
# fitImage: kernel + DTB are bundled into a signed FIT image (required for
# TI HS-SE secure boot). fitImage lives in the active rootfs at /boot/fitImage
# and is loaded by U-Boot via ext4load from the active rootfs partition.
#
# Secure-boot tiboot3 variants:
#   HS-FS (default)  tiboot3-j722s-hs-fs-evm.bin  — field-securable boards
#   HS-SE (--hs-se)  tiboot3-j722s-hs-evm.bin      — production locked boards
#
# Partition layouts:
#
#   non-RAUC (default):
#     p1  FAT16  boot (128 MiB)  tiboot3.bin, tispl.bin, u-boot.img
#     p2  ext4   rootfs          (/boot/fitImage lives here)
#     p3  ext4   overlay rwdata  (optional, --overlay-data; else tmpfs)
#
#   RAUC (--rauc):
#     p1  FAT16  boot (128 MiB)  tiboot3.bin, tispl.bin, u-boot.img
#     p2  ext4   rootfs A        (populated by this script)
#     p3  ext4   rootfs B        (left empty; filled later by 'rauc install')
#     p4  ext4   /data           (RAUC status + adaptive cache, A/B shared)
#     p5  ext4   overlay rwdata  (optional, --overlay-data; else tmpfs)
#
# The /data partition is required for RAUC adaptive update: the slot hash
# index cache and status file must survive A/B slot switches.
#
# Rootfs sources:
#   --yocto/--bsp  Yocto rootfs tarball (REQUIRED: kernel modules / firmware;
#                  also the rootfs base when --ubuntu is omitted)
#   --ubuntu       External Ubuntu/Debian rootfs tarball (OPTIONAL base). When
#                  given, kernel modules + firmware are copied from the Yocto
#                  tarball on top; fitImage comes from --fitimage or --images.
#
# Boot artifacts (resolved from --images dir, or by explicit path):
#   --tiboot3      tiboot3.bin  -> boot partition
#                  (default: tiboot3-j722s-hs-fs-evm.bin, or hs-evm.bin with --hs-se)
#   --tispl        tispl.bin    -> boot partition
#                  (default: tispl.bin-j722s-ecu1270-* or tispl.bin)
#   --uboot-img    u-boot.img   -> boot partition
#                  (default: u-boot-j722s-ecu1270-*.img or u-boot.img)
#   --fitimage     fitImage     -> rootfs /boot/fitImage
#                  (default: fitImage--*-j722s-ecu1270*.bin or fitImage)
#   --bundle       *.raucb      -> /data partition (optional; RAUC only)
#
# Examples:
#   # DEFAULT: non-RAUC, Yocto rootfs base, auto-detect all artifacts:
#   sudo ./j722s-ecu1270_flash.sh -d /dev/sdb -i ~/deploy \
#       --yocto tisdk-base-image-j722s-ecu1270.rootfs.tar.xz
#
#   # non-RAUC + Ubuntu base + Yocto modules:
#   sudo ./j722s-ecu1270_flash.sh -d /dev/sdb -i ~/deploy \
#       --ubuntu ubuntu-24.04-arm64-generic.rootfs.tar.zst \
#       --yocto  tisdk-base-image-j722s-ecu1270.rootfs.tar.xz
#
#   # non-RAUC + overlay rwdata partition:
#   sudo ./j722s-ecu1270_flash.sh -d /dev/sdb -i ~/deploy --overlay-data \
#       --yocto tisdk-base-image-j722s-ecu1270.rootfs.tar.xz
#
#   # RAUC A/B + /data (pre-stage a bundle):
#   sudo ./j722s-ecu1270_flash.sh -d /dev/sdb -i ~/deploy --rauc \
#       --yocto  tisdk-base-image-j722s-ecu1270.rootfs.tar.xz \
#       --bundle update-bundle-j722s-ecu1270.raucb
#
#   # RAUC A/B + /data + overlay rwdata:
#   sudo ./j722s-ecu1270_flash.sh -d /dev/sdb -i ~/deploy --rauc --overlay-data \
#       --yocto tisdk-base-image-j722s-ecu1270.rootfs.tar.xz
#
#   # HS-SE secure-boot board (use hs-evm tiboot3 variant):
#   sudo ./j722s-ecu1270_flash.sh -d /dev/sdb -i ~/deploy --hs-se \
#       --yocto tisdk-base-image-j722s-ecu1270.rootfs.tar.xz

set -Eeuo pipefail

PROG="${0##*/}"

# ----------------------------------------------------------------------------
# Tunables
# ----------------------------------------------------------------------------
BOOT_SIZE="128MiB"          # FAT boot partition size (p1)
ROOTFS_SIZE="5GiB"          # size of EACH rootfs partition
DATA_SIZE="15GiB"           # RAUC /data partition size
RWDATA_LABEL="rwdata"       # filesystem label of the overlay data partition
WIPE_MIB=16                 # zero the first N MiB to clear old tables

TIBOOT3=""                  # tiboot3.bin path; auto-detected when empty
TISPL=""                    # tispl.bin path; auto-detected when empty
UBOOT_IMG=""                # u-boot.img path; auto-detected when empty
FITIMAGE=""                 # fitImage path; auto-detected when empty
BUNDLE=""                   # optional *.raucb to pre-stage on /data

RAUC=0                      # 1 = RAUC A/B layout
OVERLAY_DATA=0              # 1 = add ext4 overlay rwdata partition (last)
HS_SE=0                     # 1 = prefer tiboot3-j722s-hs-evm.bin (HS-SE)

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------
log()  { printf '\033[1;34m[%s]\033[0m %s\n' "$PROG" "$*" >&2; }
ok()   { printf '\033[1;32m[%s]\033[0m %s\n' "$PROG" "$*" >&2; }
warn() { printf '\033[1;33m[%s] WARN:\033[0m %s\n' "$PROG" "$*" >&2; }
err()  { printf '\033[1;31m[%s] ERROR:\033[0m %s\n' "$PROG" "$*" >&2; }
die()  { err "$*"; exit 1; }

usage() {
    cat >&2 <<'EOF'
Usage: j722s-ecu1270_flash.sh -d <disk> --yocto <tarball> [options]

Target: Advantech ECU-1270 (TI J722S). Default non-RAUC; --rauc for A/B.

Required:
  -d, --disk <dev>        target block device (e.g. /dev/sdb, /dev/mmcblk0)
  --yocto, --bsp <file>   Yocto rootfs tarball (modules/firmware; base if no --ubuntu)

Optional:
  -i, --images <dir>      folder to resolve bare artifact names (default: .)
  --ubuntu <file>         external Ubuntu/Debian rootfs tarball (base; Yocto overlaid)
  --tiboot3 <file>        tiboot3.bin  (default: tiboot3-j722s-hs-fs-evm.bin)
  --tispl <file>          tispl.bin    (default: auto-detect tispl.bin-j722s-ecu1270-*)
  --uboot-img <file>      u-boot.img   (default: auto-detect u-boot-j722s-ecu1270-*.img)
  -f, --fitimage <file>   fitImage     (default: auto-detect fitImage--*-j722s-ecu1270*)
  --bundle <file>         *.raucb to pre-stage on /data (--rauc only, optional)
  --hs-se                 use HS-SE tiboot3 (tiboot3-j722s-hs-evm.bin) for locked boards
  -R, --rauc              RAUC A/B layout (p1 boot, p2 rootfsA, p3 rootfsB, p4 /data)
  -O, --overlay-data      add an ext4 overlay rwdata partition (last partition)
  --boot-size <sz>        FAT boot partition size (default: 128MiB)
  --rootfs-size <sz>      size of each rootfs partition (default: 5GiB)
  --data-size <sz>        RAUC /data partition size (default: 15GiB)
  -y, --yes               do not prompt for confirmation
  -h, --help              show this help

Partition layouts:

  non-RAUC (default):
    p1  FAT16  boot (128 MiB)  tiboot3.bin, tispl.bin, u-boot.img
    p2  ext4   rootfs          (/boot/fitImage)
    p3  ext4   overlay rwdata  (only with --overlay-data)

  RAUC (--rauc):
    p1  FAT16  boot (128 MiB)  tiboot3.bin, tispl.bin, u-boot.img
    p2  ext4   rootfs A        (flashed now)
    p3  ext4   rootfs B        (empty; populated by 'rauc install')
    p4  ext4   /data           (RAUC status + adaptive cache)
    p5  ext4   overlay rwdata  (only with --overlay-data)

TI K3 boot chain:  tiboot3.bin -> tispl.bin -> u-boot.img  (all on p1 FAT)
fitImage:          lives in rootfs /boot/fitImage (loaded by U-Boot via ext4load)
U-Boot env:        uboot.env on p1 FAT (written by U-Boot on first boot)
EOF
    exit "${1:-0}"
}

# Re-exec through sudo if not root.
ORIG_ARGS=()
ensure_root() {
    if [[ ${EUID} -ne 0 ]]; then
        log "elevating privileges via sudo ..."
        exec sudo -E -- "$0" ${ORIG_ARGS[@]+"${ORIG_ARGS[@]}"}
    fi
}

# Pick the right decompressor for a tarball by extension, then run tar.
tar_xf() {
    local tb="$1"; shift
    local dc=()
    case "$tb" in
        *.zst|*.tzst) command -v unzstd >/dev/null || die "zstd not installed (need unzstd for $tb)"; dc=(--use-compress-program=unzstd) ;;
        *.xz)         dc=(-J) ;;
        *.gz|*.tgz)   dc=(-z) ;;
        *.bz2|*.tbz2) dc=(-j) ;;
        *.tar)        dc=() ;;
        *) warn "unknown tar extension for $tb; letting tar autodetect" ;;
    esac
    tar "${dc[@]}" -f "$tb" "$@"
}

# Reject rootfs sources that are not tarballs.
#
# Yocto's deploy dir ships several rootfs artifacts side by side (.tar.xz,
# .ext4, .wic.xz, .cpio.xz) and only the tarball can be extracted onto an
# already-formatted partition. A raw .ext4 image is especially treacherous:
# its first 1 KiB is zero padding, which GNU tar reads as an end-of-archive
# marker — so 'tar -x' extracts nothing and still exits 0, leaving an empty
# rootfs that panics on the board with "No working init found".
assert_tarball() {
    local f="$1" what="$2"
    case "$f" in
        *.tar|*.tar.*|*.tgz|*.tzst|*.tbz2) return 0 ;;
    esac
    err "$what must be a rootfs tarball, got: ${f##*/}"
    err "  raw filesystem images (.ext4/.wic/.img/.cpio) cannot be extracted with tar"
    case "$f" in
        *.rootfs*.ext4|*.rootfs*.wic*|*.rootfs*.cpio*)
            err "  try the matching tarball: ${f%%.rootfs*}.rootfs.tar.xz" ;;
    esac
    exit 1
}

# Resolve a file argument: accept an absolute/relative path, or a bare name
# inside the --images folder. Echoes an absolute path.
resolve_artifact() {
    local f="$1"
    [[ -n "$f" ]] || { printf '%s' ""; return; }
    if [[ -e "$f" ]];         then readlink -f "$f"; return; fi
    if [[ -e "$IMAGES/$f" ]]; then readlink -f "$IMAGES/$f"; return; fi
    printf '%s' "$f"
}

# Auto-detect a file by glob pattern inside $IMAGES; echo the first match or "".
auto_detect() {
    local pattern="$1"
    local hit
    hit=$(find "$IMAGES" -maxdepth 1 -name "$pattern" | sort | head -1)
    printf '%s' "$hit"
}

# Convert a size string (8MiB, 6GiB, 512M, 2G, bare number = MiB) to MiB.
to_mib() {
    local v="$1"
    if   [[ "$v" =~ ^([0-9]+)[[:space:]]*[Gg]i?[Bb]?$ ]]; then echo $(( ${BASH_REMATCH[1]} * 1024 ))
    elif [[ "$v" =~ ^([0-9]+)[[:space:]]*[Mm]i?[Bb]?$ ]]; then echo "${BASH_REMATCH[1]}"
    elif [[ "$v" =~ ^([0-9]+)$ ]];                        then echo "${BASH_REMATCH[1]}"
    else die "cannot parse size '$v' (use e.g. 5GiB, 128MiB)"
    fi
}

# ----------------------------------------------------------------------------
# Disk selection (fzf if available, else manual prompt)
# ----------------------------------------------------------------------------
list_disks() {
    lsblk -d -p -n -o NAME,SIZE,MODEL,TRAN | grep -E '(usb|mmc)' \
        || lsblk -d -p -n -o NAME,SIZE,MODEL,TRAN
}

select_disk() {
    echo "" >&2
    log "available disks:"
    list_disks >&2
    echo "" >&2
    local disk=""
    if command -v fzf >/dev/null 2>&1; then
        disk=$(list_disks | fzf --prompt="Select target disk: " --height=12 | awk '{print $1}')
    else
        read -rp "Enter target disk (e.g. /dev/sdb, /dev/mmcblk0): " disk
    fi
    printf '%s' "$disk"
}

# ----------------------------------------------------------------------------
# Cleanup
# ----------------------------------------------------------------------------
WORKDIR=""
cleanup() {
    local rc=$?
    [[ -n "$WORKDIR" ]] || return $rc
    local m
    for m in $(awk -v r="$WORKDIR/" '$2 ~ "^"r {print $2}' /proc/self/mounts | sort -r); do
        umount "$m" 2>/dev/null || umount -l "$m" 2>/dev/null || true
    done
    if [[ $rc -eq 0 ]]; then
        rm -rf "$WORKDIR"
    else
        warn "left working dir for inspection: $WORKDIR"
    fi
    return $rc
}

# ----------------------------------------------------------------------------
# Partition the disk
#
# TI J722S layout always starts with a FAT16 boot partition (p1) for the
# K3 bootloader chain. The rootfs partition(s) follow from p2 onwards.
#
#   non-RAUC: p1 FAT boot | p2 rootfs [| p3 overlay]
#   RAUC:     p1 FAT boot | p2 rootfsA | p3 rootfsB | p4 /data [| p5 overlay]
# ----------------------------------------------------------------------------
partition_disk() {
    local disk="$1"

    log "unmounting any existing partitions on $disk"
    umount "${disk}"* 2>/dev/null || true

    log "wiping first ${WIPE_MIB} MiB of $disk"
    dd if=/dev/zero of="$disk" bs=1M count="$WIPE_MIB" conv=fsync status=none
    sync

    local boot_mib rootfs_mib data_mib
    boot_mib="$(to_mib "$BOOT_SIZE")"
    rootfs_mib="$(to_mib "$ROOTFS_SIZE")"
    data_mib="$(to_mib "$DATA_SIZE")"

    # All sizes in MiB; parted uses MiB boundaries.
    # Use 1 MiB start to align with erase blocks (the original scripts start
    # at 1049 kB ≈ 1 MiB; we use an exact MiB boundary for simplicity).
    local boot_start=1
    local boot_end=$(( boot_start + boot_mib ))        # p1 end
    local rs_end=$(( boot_end + rootfs_mib ))           # end of first rootfs (p2)

    parted -s "$disk" mklabel msdos

    if [[ $RAUC -eq 1 ]]; then
        local rb_end=$(( rs_end + rootfs_mib ))          # end of rootfs B (p3)
        local data_end=$(( rb_end + data_mib ))          # end of /data (p4)
        log "RAUC layout: p1 boot (${BOOT_SIZE}), p2 rootfsA (${ROOTFS_SIZE}), p3 rootfsB (${ROOTFS_SIZE}), p4 /data (${DATA_SIZE})$([[ $OVERLAY_DATA -eq 1 ]] && echo ', p5 overlay (rest)')"
        parted -s "$disk" mkpart primary fat16 "${boot_start}MiB" "${boot_end}MiB"   # p1 boot
        parted -s "$disk" mkpart primary ext4  "${boot_end}MiB"   "${rs_end}MiB"     # p2 rootfsA
        parted -s "$disk" mkpart primary ext4  "${rs_end}MiB"     "${rb_end}MiB"     # p3 rootfsB
        if [[ $OVERLAY_DATA -eq 1 ]]; then
            parted -s "$disk" mkpart primary ext4 "${rb_end}MiB"   "${data_end}MiB"  # p4 /data
            parted -s "$disk" mkpart primary ext4 "${data_end}MiB" 100%              # p5 overlay
        else
            parted -s "$disk" mkpart primary ext4 "${rb_end}MiB" 100%                # p4 /data
        fi
    else
        if [[ $OVERLAY_DATA -eq 1 ]]; then
            log "non-RAUC layout: p1 boot (${BOOT_SIZE}), p2 rootfs (${ROOTFS_SIZE}), p3 overlay (rest)"
            parted -s "$disk" mkpart primary fat16 "${boot_start}MiB" "${boot_end}MiB"  # p1 boot
            parted -s "$disk" mkpart primary ext4  "${boot_end}MiB"   "${rs_end}MiB"    # p2 rootfs
            parted -s "$disk" mkpart primary ext4  "${rs_end}MiB"     100%              # p3 overlay
        else
            log "non-RAUC layout: p1 boot (${BOOT_SIZE}), p2 rootfs (rest)"
            parted -s "$disk" mkpart primary fat16 "${boot_start}MiB" "${boot_end}MiB"  # p1 boot
            parted -s "$disk" mkpart primary ext4  "${boot_end}MiB"   100%              # p2 rootfs
        fi
    fi
    parted -s "$disk" set 1 boot on
    parted -s "$disk" set 1 lba on

    sync
    partprobe "$disk" 2>/dev/null || true
    udevadm settle 2>/dev/null || true
    sleep 1

    log "formatting p1 (FAT16, label BOOT)"
    mkfs.vfat -F 16 "${disk}${P}1" -n BOOT

    if [[ $RAUC -eq 1 ]]; then
        log "formatting p2 rootfsA (ext4, label rootfs0)"
        mkfs.ext4 -F -L rootfs0 "${disk}${P}2"
        log "formatting p3 rootfsB (ext4, label rootfs1)"
        mkfs.ext4 -F -L rootfs1 "${disk}${P}3"
        if [[ $OVERLAY_DATA -eq 1 ]]; then
            log "formatting p4 /data (ext4, label data)"
            mkfs.ext4 -F -L data "${disk}${P}4"
            log "formatting p5 overlay rwdata (ext4, label ${RWDATA_LABEL})"
            mkfs.ext4 -F -L "$RWDATA_LABEL" "${disk}${P}5"
        else
            log "formatting p4 /data (ext4, label data)"
            mkfs.ext4 -F -L data "${disk}${P}4"
        fi
    else
        log "formatting p2 rootfs (ext4, label rootfs)"
        mkfs.ext4 -F -L rootfs "${disk}${P}2"
        if [[ $OVERLAY_DATA -eq 1 ]]; then
            log "formatting p3 overlay rwdata (ext4, label ${RWDATA_LABEL})"
            mkfs.ext4 -F -L "$RWDATA_LABEL" "${disk}${P}3"
        fi
    fi
}

# ----------------------------------------------------------------------------
# Copy TI K3 bootloader files to the FAT boot partition (p1)
#
# Unlike i.MX imx-boot (single file written at a raw offset), TI K3 uses
# three files that must be present on the FAT boot partition by name.
# U-Boot will also create uboot.env here on first boot.
# ----------------------------------------------------------------------------
populate_boot_partition() {
    local mnt="$1"

    log "installing TI K3 bootloader chain -> ${mnt}/"
    log "  tiboot3 : ${TIBOOT3##*/}"
    log "  tispl   : ${TISPL##*/}"
    log "  u-boot  : ${UBOOT_IMG##*/}"

    cp -L "$TIBOOT3"  "$mnt/tiboot3.bin"
    cp -L "$TISPL"    "$mnt/tispl.bin"
    cp -L "$UBOOT_IMG" "$mnt/u-boot.img"

    ok "boot partition populated (uboot.env will be created by U-Boot on first boot)"
}

# ----------------------------------------------------------------------------
# Populate the active rootfs partition (p2 for non-RAUC, p2/p3 for RAUC)
#
# Two modes:
#   --ubuntu set   External Ubuntu/Debian base + Yocto modules/firmware overlay
#   --ubuntu empty Yocto rootfs tarball is the complete base
#
# fitImage is always installed to /boot/fitImage afterwards (if found).
# ----------------------------------------------------------------------------
populate_rootfs() {
    local mnt="$1"

    if [[ -n "$UBUNTU" ]]; then
        log "extracting external Ubuntu/Debian rootfs: ${UBUNTU##*/}  (may take a while)"
        tar_xf "$UBUNTU" --numeric-owner -x -C "$mnt"

        log "extracting Yocto modules/firmware/boot from: ${BSP##*/}"
        local bsp_extract="$WORKDIR/bsp_extract"
        mkdir -p "$bsp_extract"
        tar_xf "$BSP" --numeric-owner -x -C "$bsp_extract" --wildcards \
            '*/lib/modules/*' '*/lib/firmware/*' '*/boot/*' \
            'lib/modules/*' 'lib/firmware/*' 'boot/*' 2>/dev/null || true

        local mods fwdir bootdir bsproot
        mods=$(find "$bsp_extract" -type d -path '*/lib/modules' | head -1)
        [[ -n "$mods" ]] || die "no kernel modules found in Yocto tarball ($BSP)"
        bsproot="${mods%/lib/modules}"
        fwdir="$bsproot/lib/firmware"
        bootdir=$(find "$bsp_extract" -type d -name boot | head -1)

        log "overlaying kernel modules -> /usr/lib/modules"
        install -d "$mnt/usr/lib/modules"
        cp -a "$mods/." "$mnt/usr/lib/modules/"
        KVER=$(ls "$mods" | head -1)
        log "kernel version (KVER): $KVER"

        if [[ -d "$mnt/usr/lib/modules/$KVER/build" ]]; then
            log "kernel-devsrc tree found ($KVER/build) — creating /usr/src/kernel symlink"
            install -d "$mnt/usr/src"
            ln -sfn "/usr/lib/modules/$KVER/source" "$mnt/usr/src/kernel"
        else
            warn "kernel-devsrc tree missing: usr/lib/modules/$KVER/build/ not in Yocto tarball"
            warn "  on-target out-of-tree module builds will fail (add kernel-devsrc to IMAGE_INSTALL)"
        fi

        if [[ -d "$fwdir" ]]; then
            log "overlaying firmware -> /usr/lib/firmware"
            install -d "$mnt/usr/lib/firmware"
            cp -a "$fwdir/." "$mnt/usr/lib/firmware/"
        else
            warn "no firmware dir in Yocto tarball; WiFi/VPU/NPU blobs may be missing"
        fi

        # Provide a baseline /boot from the Yocto tarball.
        if [[ -n "$bootdir" && -d "$bootdir" ]]; then
            log "overlaying baseline /boot contents from Yocto tarball"
            install -d "$mnt/boot"
            cp -aL "$bootdir/." "$mnt/boot/" 2>/dev/null || cp -a "$bootdir/." "$mnt/boot/"
        fi

        log "rebuilding module dependencies (depmod -b)"
        depmod -a -b "$mnt" "$KVER" 2>/dev/null \
            || warn "depmod failed on host; run 'sudo depmod -a' on the target after first boot"
    else
        log "extracting Yocto rootfs (base): ${BSP##*/}  (may take a while)"
        tar_xf "$BSP" --numeric-owner -x -C "$mnt"

        local mods
        mods=$(find "$mnt" -maxdepth 5 -type d -path '*/lib/modules' | head -1)
        if [[ -n "$mods" ]]; then
            KVER=$(ls "$mods" | head -1)
            log "kernel version (KVER): $KVER"
        else
            warn "no /lib/modules found in Yocto rootfs tarball"
        fi
    fi

    # Sanity check: the kernel needs an init and a /dev mountpoint, otherwise
    # the board panics with "No working init found" / "devtmpfs: error mounting".
    # This catches an extraction that silently produced nothing.
    local init_found=0 cand
    for cand in sbin/init usr/sbin/init bin/init usr/lib/systemd/systemd lib/systemd/systemd; do
        if [[ -e "$mnt/$cand" || -L "$mnt/$cand" ]]; then init_found=1; break; fi
    done
    if [[ $init_found -eq 0 ]]; then
        err "rootfs at $mnt has no init — the board would panic on boot"
        err "  contents: $(ls -A "$mnt" | tr '\n' ' ')"
        die "rootfs extraction produced nothing usable (wrong ${BSP##*/}?)"
    fi
    [[ -d "$mnt/dev" ]] || warn "rootfs has no /dev — devtmpfs will fail to mount"

    # Install fitImage to /boot/fitImage.
    # TI HS-SE secure boot requires bootm with the FIT image's config node;
    # a separate Image + DTB is NOT used.
    if [[ -n "$FITIMAGE" ]]; then
        log "installing fitImage -> /boot/fitImage: ${FITIMAGE##*/}"
        install -d "$mnt/boot"
        cp -L "$FITIMAGE" "$mnt/boot/fitImage"
    else
        warn "fitImage not provided; /boot/fitImage will come from the Yocto rootfs tarball"
        warn "  (pass --fitimage for an explicit FIT image)"
    fi
}

# ----------------------------------------------------------------------------
# Pre-stage a RAUC bundle on the /data partition (optional convenience)
# ----------------------------------------------------------------------------
populate_data_partition() {
    local mnt="$1"
    [[ -n "$BUNDLE" ]] || return 0
    log "pre-staging RAUC bundle on /data: ${BUNDLE##*/}"
    cp -L "$BUNDLE" "$mnt/"
    ok "bundle copied to /data/${BUNDLE##*/}"
}

# ----------------------------------------------------------------------------
# Argument parsing + main
# ----------------------------------------------------------------------------
DISK=""
IMAGES="."
UBUNTU=""
BSP=""
ASSUME_YES=0
KVER=""

main() {
    ORIG_ARGS=("$@")

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d|--disk|--device)     DISK="${2:-}"; shift 2 ;;
            -i|--images)            IMAGES="${2:-}"; shift 2 ;;
            --ubuntu)               UBUNTU="${2:-}"; shift 2 ;;
            -b|--bsp|--yocto)       BSP="${2:-}"; shift 2 ;;
            --tiboot3)              TIBOOT3="${2:-}"; shift 2 ;;
            --tispl)                TISPL="${2:-}"; shift 2 ;;
            --uboot-img)            UBOOT_IMG="${2:-}"; shift 2 ;;
            -f|--fitimage)          FITIMAGE="${2:-}"; shift 2 ;;
            --bundle)               BUNDLE="${2:-}"; shift 2 ;;
            --hs-se)                HS_SE=1; shift ;;
            -R|--rauc)              RAUC=1; shift ;;
            -O|--overlay-data)      OVERLAY_DATA=1; shift ;;
            --boot-size)            BOOT_SIZE="${2:-}"; shift 2 ;;
            --rootfs-size)          ROOTFS_SIZE="${2:-}"; shift 2 ;;
            --data-size)            DATA_SIZE="${2:-}"; shift 2 ;;
            -y|--yes)               ASSUME_YES=1; shift ;;
            -h|--help)              usage 0 ;;
            *) err "unknown option: $1"; usage 1 ;;
        esac
    done

    ensure_root

    [[ -d "$IMAGES" ]] || die "images folder not found: $IMAGES"
    IMAGES="$(cd "$IMAGES" && pwd -P)"

    [[ -n "$BSP" ]] || die "missing --yocto/--bsp <Yocto rootfs tarball>"
    BSP="$(resolve_artifact "$BSP")"
    [[ -f "$BSP" ]] || die "Yocto rootfs not found: $BSP"
    assert_tarball "$BSP" "--yocto/--bsp"

    if [[ -n "$UBUNTU" ]]; then
        UBUNTU="$(resolve_artifact "$UBUNTU")"
        [[ -f "$UBUNTU" ]] || die "Ubuntu/Debian rootfs not found: $UBUNTU"
        assert_tarball "$UBUNTU" "--ubuntu"
    fi

    # ---- Resolve tiboot3 ----
    if [[ -n "$TIBOOT3" ]]; then
        TIBOOT3="$(resolve_artifact "$TIBOOT3")"
    elif [[ $HS_SE -eq 1 ]]; then
        TIBOOT3="$(auto_detect 'tiboot3-j722s-hs-evm.bin')"
        [[ -n "$TIBOOT3" ]] || die "HS-SE tiboot3 not found (tiboot3-j722s-hs-evm.bin) in $IMAGES; use --tiboot3"
        log "auto-detected HS-SE tiboot3: ${TIBOOT3##*/}"
    else
        TIBOOT3="$(auto_detect 'tiboot3-j722s-hs-fs-evm.bin')"
        if [[ -z "$TIBOOT3" ]]; then
            TIBOOT3="$(auto_detect 'tiboot3*.bin')"
        fi
        [[ -n "$TIBOOT3" ]] || die "tiboot3 not found in $IMAGES; use --tiboot3 or --hs-se"
        log "auto-detected tiboot3: ${TIBOOT3##*/}"
    fi
    [[ -f "$TIBOOT3" ]] || die "tiboot3 not found: $TIBOOT3"

    # ---- Resolve tispl ----
    if [[ -n "$TISPL" ]]; then
        TISPL="$(resolve_artifact "$TISPL")"
    else
        TISPL="$(auto_detect 'tispl.bin-j722s-ecu1270-*')"
        if [[ -z "$TISPL" ]]; then
            TISPL="$(auto_detect 'tispl.bin')"
        fi
        [[ -n "$TISPL" ]] || die "tispl.bin not found in $IMAGES; use --tispl"
        log "auto-detected tispl: ${TISPL##*/}"
    fi
    [[ -f "$TISPL" ]] || die "tispl.bin not found: $TISPL"

    # ---- Resolve u-boot.img ----
    if [[ -n "$UBOOT_IMG" ]]; then
        UBOOT_IMG="$(resolve_artifact "$UBOOT_IMG")"
    else
        UBOOT_IMG="$(auto_detect 'u-boot-j722s-ecu1270-*.img')"
        if [[ -z "$UBOOT_IMG" ]]; then
            UBOOT_IMG="$(auto_detect 'u-boot.img')"
        fi
        [[ -n "$UBOOT_IMG" ]] || die "u-boot.img not found in $IMAGES; use --uboot-img"
        log "auto-detected u-boot.img: ${UBOOT_IMG##*/}"
    fi
    [[ -f "$UBOOT_IMG" ]] || die "u-boot.img not found: $UBOOT_IMG"

    # ---- Resolve fitImage ----
    if [[ -n "$FITIMAGE" ]]; then
        FITIMAGE="$(resolve_artifact "$FITIMAGE")"
        [[ -f "$FITIMAGE" ]] || die "fitImage not found: $FITIMAGE"
    else
        FITIMAGE="$(auto_detect 'fitImage--*-j722s-ecu1270*.bin')"
        if [[ -z "$FITIMAGE" ]]; then
            FITIMAGE="$(auto_detect 'fitImage')"
        fi
        if [[ -n "$FITIMAGE" ]]; then
            log "auto-detected fitImage: ${FITIMAGE##*/}"
        else
            warn "fitImage not found in $IMAGES; /boot/fitImage will come from the Yocto rootfs"
            warn "  (pass --fitimage for an explicit FIT image; required for HS-SE secure boot)"
        fi
    fi

    # ---- Resolve bundle ----
    if [[ -n "$BUNDLE" ]]; then
        BUNDLE="$(resolve_artifact "$BUNDLE")"
        [[ -f "$BUNDLE" ]] || die "RAUC bundle not found: $BUNDLE"
        [[ $RAUC -eq 1 ]] || die "--bundle requires --rauc (bundle goes on the /data partition)"
    fi

    # ---- Disk ----
    [[ -n "$DISK" ]] || DISK="$(select_disk)"
    [[ -n "$DISK" ]] || die "no target disk selected"
    [[ -b "$DISK" ]] || die "$DISK is not a block device"

    # Partition node suffix: mmcblk0p1 / nvme0n1p1 vs sdb1.
    if [[ "$DISK" =~ [0-9]$ ]]; then P="p"; else P=""; fi

    # ---- Confirmation ----
    echo "" >&2
    echo "==================================================" >&2
    echo "  ECU-1270 (TI J722S) SD/eMMC flash" >&2
    echo "==================================================" >&2
    printf "  Target disk   : %s\n"  "$DISK" >&2
    printf "  Layout mode   : %s\n"  "$([[ $RAUC -eq 1 ]] && echo 'RAUC A/B' || echo 'non-RAUC')" >&2
    printf "  Ubuntu base   : %s\n"  "${UBUNTU:-(none; using Yocto rootfs)}" >&2
    printf "  Yocto rootfs  : %s\n"  "$BSP" >&2
    printf "  tiboot3       : %s\n"  "$TIBOOT3" >&2
    printf "  tispl         : %s\n"  "$TISPL" >&2
    printf "  u-boot.img    : %s\n"  "$UBOOT_IMG" >&2
    printf "  fitImage      : %s\n"  "${FITIMAGE:-(from rootfs tarball)}" >&2
    printf "  secure-boot   : %s\n"  "$([[ $HS_SE -eq 1 ]] && echo 'HS-SE' || echo 'HS-FS (default)')" >&2
    if [[ -n "$BUNDLE" ]]; then
        printf "  RAUC bundle   : %s\n" "$BUNDLE" >&2
    fi
    if [[ $RAUC -eq 1 ]]; then
        printf "  partitions    : p1 boot (%s FAT), p2 rootfsA (%s), p3 rootfsB (%s), p4 /data (%s)%s\n" \
            "$BOOT_SIZE" "$ROOTFS_SIZE" "$ROOTFS_SIZE" "$DATA_SIZE" \
            "$([[ $OVERLAY_DATA -eq 1 ]] && echo ", p5 rwdata (rest)")" >&2
    elif [[ $OVERLAY_DATA -eq 1 ]]; then
        printf "  partitions    : p1 boot (%s FAT), p2 rootfs (%s), p3 rwdata (rest, label %s)\n" \
            "$BOOT_SIZE" "$ROOTFS_SIZE" "$RWDATA_LABEL" >&2
    else
        printf "  partitions    : p1 boot (%s FAT), p2 rootfs (rest)\n" "$BOOT_SIZE" >&2
    fi
    echo "==================================================" >&2
    warn "this will DESTROY ALL DATA on $DISK"
    if [[ $ASSUME_YES -ne 1 ]]; then
        local confirm=""
        read -rp "Type 'yes' to continue: " confirm
        [[ "$confirm" == "yes" ]] || die "aborted by user"
    fi

    WORKDIR="$(mktemp -d -t j722s-ecu1270-flash-XXXXXX)"
    trap cleanup EXIT INT TERM

    # ---- Partition ----
    partition_disk "$DISK"

    # ---- Populate boot partition (p1 FAT) ----
    local mnt_boot="$WORKDIR/mnt_boot"
    mkdir -p "$mnt_boot"
    log "mounting ${DISK}${P}1 (boot FAT) -> $mnt_boot"
    mount "${DISK}${P}1" "$mnt_boot"
    populate_boot_partition "$mnt_boot"
    log "syncing and unmounting boot partition"
    sync; umount "$mnt_boot"

    # ---- Populate rootfs A (p2) ----
    local mnt_rootfs="$WORKDIR/mnt_rootfs"
    mkdir -p "$mnt_rootfs"
    log "mounting ${DISK}${P}2 (rootfsA / rootfs) -> $mnt_rootfs"
    mount "${DISK}${P}2" "$mnt_rootfs"
    populate_rootfs "$mnt_rootfs"
    log "rootfs contents:"
    ls "$mnt_rootfs" | sed 's/^/    /' >&2
    if [[ -d "$mnt_rootfs/boot" ]]; then
        log "/boot contents:"
        ls -lh "$mnt_rootfs/boot" | sed 's/^/    /' >&2
    fi
    log "syncing and unmounting rootfs"
    sync; umount "$mnt_rootfs"

    # ---- RAUC: populate /data (p4) ----
    if [[ $RAUC -eq 1 ]]; then
        local mnt_data="$WORKDIR/mnt_data"
        mkdir -p "$mnt_data"
        log "mounting ${DISK}${P}4 (/data) -> $mnt_data"
        mount "${DISK}${P}4" "$mnt_data"
        populate_data_partition "$mnt_data"
        log "syncing and unmounting /data"
        sync; umount "$mnt_data"
    fi

    log "flushing disk caches"
    blockdev --flushbufs "$DISK" 2>/dev/null || true
    sync

    ok "done — ECU-1270 SD/eMMC ready (KVER=${KVER:-unknown})"
    echo "" >&2
    echo "  Layout:" >&2
    echo "    ${DISK}${P}1 (FAT16) : boot — tiboot3.bin, tispl.bin, u-boot.img" >&2
    if [[ $RAUC -eq 1 ]]; then
        echo "    ${DISK}${P}2 (ext4)  : rootfs A, /boot/fitImage (active slot)" >&2
        echo "    ${DISK}${P}3 (ext4)  : rootfs B (empty; 'rauc install' populates it)" >&2
        if [[ $OVERLAY_DATA -eq 1 ]]; then
            echo "    ${DISK}${P}4 (ext4)  : /data (RAUC status + adaptive cache)" >&2
            echo "    ${DISK}${P}5 (ext4)  : overlay rwdata (label ${RWDATA_LABEL})" >&2
            echo "" >&2
            echo "  For overlay root, set kernel cmdline: overlayrwdev=/dev/mmcblkXp5" >&2
        else
            echo "    ${DISK}${P}4 (ext4)  : /data (RAUC status + adaptive cache)" >&2
        fi
        if [[ -n "$BUNDLE" ]]; then
            echo "" >&2
            echo "  RAUC bundle pre-staged on /data: ${BUNDLE##*/}" >&2
            echo "  To install: rauc install /data/${BUNDLE##*/}" >&2
        fi
    else
        echo "    ${DISK}${P}2 (ext4)  : rootfs, /boot/fitImage" >&2
        if [[ $OVERLAY_DATA -eq 1 ]]; then
            echo "    ${DISK}${P}3 (ext4)  : overlay rwdata (label ${RWDATA_LABEL})" >&2
            echo "" >&2
            echo "  For overlay root, set kernel cmdline: overlayrwdev=/dev/mmcblkXp3" >&2
        fi
    fi
    echo "" >&2
    echo "  U-Boot bootcmd:" >&2
    if [[ $RAUC -eq 1 ]]; then
        echo "    RAUC_ENABLED=1 → run rauc_bootcmd (A/B slot selection via BOOT_ORDER)" >&2
    else
        echo "    RAUC_ENABLED=0 → run normal_bootcmd (fixed p2, no slot selection)" >&2
    fi
    echo "" >&2
    echo "  Remove the card/complete the flash, insert it into the ECU-1270, and power on." >&2
}

main "$@"
