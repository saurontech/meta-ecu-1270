#!/bin/bash
# ECU-1270 encrypted data partition: unlock / mount, and provision on demand.
# Values below are substituted at build time by ecu1270-luks-data_1.0.bb.
# -E so the ERR trap set in provision() also fires inside called functions.
set -eEuo pipefail

KEY_MODE="@LUKS_DATA_KEY_MODE@"
DEV_SPEC="@LUKS_DATA_DEVICE@"
MAPPER="@LUKS_DATA_MAPPER@"
MOUNTPOINT="@LUKS_DATA_MOUNT@"
RECOVERY_KEY="@LUKS_DATA_RECOVERY_KEY@"
AUTO_PROVISION="@LUKS_DATA_AUTO_PROVISION@"
PBKDF_ITER="@LUKS_DATA_PBKDF_ITER@"
PBKDF_MEMORY="@LUKS_DATA_PBKDF_MEMORY@"
PBKDF_PARALLEL="@LUKS_DATA_PBKDF_PARALLEL@"
RAUC_ENABLED="@RAUC_ENABLED@"

KEYFILE=/etc/ecu1270/data.key
RECOVERY_TMP=/run/luks-recovery.key
BOOTSTRAP_TMP=/run/luks-bootstrap.key
LABEL_READY="ecu1270"
LABEL_WIP="ecu1270-wip"
DEV_TIMEOUT=10
# LUKS2 payload offset: zeroing this much destroys the header and every keyslot.
HEADER_MIB=16

log()  { echo "luks-data: $*"; }
warn() { echo "luks-data: WARNING: $*" >&2; }
die()  { echo "luks-data: FATAL: $*" >&2; exit 1; }

# $1 = banner text. /run is tmpfs, so this is the only chance to see the key.
print_recovery_key() {
    [ -s "$RECOVERY_TMP" ] || return 0
    cat >&2 <<EOF

  ============================================================
   $1
   for $TARGET
       $(cat "$RECOVERY_TMP")
   Store it off-device against this unit's serial number. /run is
   tmpfs -- a reboot destroys it. Type it back exactly as shown,
   with no trailing spaces or newline.
  ============================================================

EOF
}

wipe_tmp_keys() {
    local f
    for f in "$RECOVERY_TMP" "$BOOTSTRAP_TMP"; do
        [ -e "$f" ] || continue
        shred -u "$f" 2>/dev/null || rm -f "$f"
    done
}

# ---------------------------------------------------------------- flag table
contract_table() {
    cat >&2 <<'EOF'

      flash flags              LUKS target      MBR?
      --rauc                   part:4           ok    (the layout we ship)
      --appdata                part:3           ok
      --rauc --appdata         part:5           NO    (needs GPT)
      (--overlay-data does not affect the number)

  NOTE: ECU-1270 has a FAT boot partition at p1. On THIS board part:3 is rootfs
  slot B and part:1 is the boot partition.

  The layout is created by tools/flash/j722s-ecu1270_flash.sh, so WHICH
  number holds the target depends on the flags that card was flashed with.
  Fix either end: rebuild with a matching LUKS_DATA_DEVICE, or re-flash with
  flags matching this image.
EOF
}

# ---------------------------------------------------------------- device spec
# part:N -> Nth partition of the boot device, inferred from /proc/cmdline root=
# (never hardcode mmcblk0/mmcblk1).
root_base_dev() {
    local r
    r=$(grep -oE 'root=/dev/[a-zA-Z0-9]+' /proc/cmdline | head -n1 | sed 's#root=/dev/##')
    [ -n "$r" ] || die "cannot find 'root=/dev/...' in /proc/cmdline"
    echo "${r%p[0-9]*}"
}

root_part_dev() {
    local r
    r=$(grep -oE 'root=/dev/[a-zA-Z0-9]+' /proc/cmdline | head -n1 | sed 's#root=/dev/##')
    echo "/dev/${r}"
}

resolve_target() {
    case "$DEV_SPEC" in
        part:[0-9]*) : ;;
        "")  die "LUKS_DATA_DEVICE is empty; this image was built wrong" ;;
        *)   die "LUKS_DATA_DEVICE must be 'part:N', got '$DEV_SPEC'" ;;
    esac
    PART_NUM="${DEV_SPEC#part:}"
    BASE_DEV="$(root_base_dev)"
    TARGET="/dev/${BASE_DEV}p${PART_NUM}"
}

wait_for_dev() {
    local d="$1" i=0
    while [ ! -e "$d" ]; do
        i=$((i + 1))
        [ "$i" -ge "$DEV_TIMEOUT" ] && return 1
        sleep 1
    done
    return 0
}

# ---------------------------------------------------------------- guards
# Split out: the WIP-rebuild path wipes the header before provision() runs.
guard_not_rootfs() {
    local rootpart
    rootpart="$(root_part_dev)"
    [ "$TARGET" != "$rootpart" ] || \
        die "target $TARGET is the running rootfs (root=$rootpart). Refusing."
}

# Answer "will encrypting this destroy something?" -- not "does it have a fs?".
run_guards() {
    local mnt fstype

    # (0) never the partition root= points at
    guard_not_rootfs

    # (0b) p1 is always the FAT boot partition; it's not root=, so guard (0) misses it.
    if [ "$PART_NUM" = "1" ]; then
        echo "luks-data: FATAL: part:1 is the FAT boot partition on ECU-1270." >&2
        contract_table
        exit 1
    fi

    # (0c) with RAUC on, root= only names the current slot; a freshly flashed
    # slot B is empty, so guards (1)/(2) would miss it too.
    if [ "$RAUC_ENABLED" = "1" ] && { [ "$PART_NUM" = "2" ] || [ "$PART_NUM" = "3" ]; }; then
        echo "luks-data: FATAL: part:$PART_NUM is a RAUC rootfs slot (p2=A, p3=B)." >&2
        echo "  part:3 was correct on ECU-150v2; on this board it is slot B." >&2
        contract_table
        exit 1
    fi

    # (1) completely blank -> nothing to destroy
    fstype="$(blkid -o value -s TYPE "$TARGET" 2>/dev/null || true)"
    if [ -z "$fstype" ]; then
        log "target $TARGET has no filesystem signature, safe to format"
        return 0
    fi

    # (2) has a filesystem -> mount read-only using blkid's reported type
    # (p1 is vfat; a hardcoded ext4 would misreport this as corruption).
    mnt="$(mktemp -d)"
    if ! mount -o ro -t "$fstype" "$TARGET" "$mnt" 2>/dev/null; then
        rmdir "$mnt"
        # (3) unmountable / unrecognised -> refuse conservatively
        die "target $TARGET has a '$fstype' signature but cannot be mounted read-only. Refusing."
    fi
    if [ -n "$(find "$mnt" -mindepth 1 ! -name lost+found -print -quit 2>/dev/null)" ]; then
        warn "target $TARGET ($fstype) is NOT empty:"
        find "$mnt" -mindepth 1 -maxdepth 1 ! -name lost+found | sed 's/^/luks-data:   /' >&2
        umount "$mnt"; rmdir "$mnt"
        cat >&2 <<EOF
luks-data: FATAL: refusing to encrypt a partition that has files on it.

  A freshly flashed data partition is empty, so something put these there.

  If they are reproducible (for example an OTA bundle you copied over
  manually), remove them and retry -- mount ${TARGET} and delete them.

  If this is an in-service unit with real data, migrate it instead
  (back up, luksFormat, restore). Do NOT just delete.
EOF
        exit 1
    fi
    umount "$mnt"; rmdir "$mnt"
    log "target $TARGET ($fstype) is empty, safe to format"
    return 0
}

# ---------------------------------------------------------------- unlock
# Returns non-zero on a failed open instead of dying: main() has to tell
# "cannot open" apart from "real failure" before deciding what to do.
unlock() {
    [ -b "/dev/mapper/$MAPPER" ] && return 0
    case "$KEY_MODE" in
        tpm)
            # --token-only: a oneshot service has no tty, so never fall back to a passphrase prompt.
            cryptsetup open --token-only "$TARGET" "$MAPPER" || return 1
            ;;
        keyfile)
            [ -f "$KEYFILE" ] || die "keyfile $KEYFILE missing"
            cryptsetup open --key-file "$KEYFILE" "$TARGET" "$MAPPER" || return 1
            ;;
        *) die "unknown LUKS_DATA_KEY_MODE '$KEY_MODE'" ;;
    esac
    log "unlocked -> /dev/mapper/$MAPPER"
}

mount_target() {
    mkdir -p "$MOUNTPOINT"
    mountpoint -q "$MOUNTPOINT" || mount "/dev/mapper/$MAPPER" "$MOUNTPOINT"
    log "mounted $MOUNTPOINT"
}

luks_label() {
    cryptsetup luksDump "$TARGET" 2>/dev/null | awk '/^Label:/{print $2; exit}'
}

# ---------------------------------------------------------------- provision
provision() {
    local boot_key drop_boot=0
    local -a pbkdf=()

    log "provisioning $TARGET (mode: $KEY_MODE, recovery keyslot: $([ "$RECOVERY_KEY" = 1 ] && echo yes || echo no))"
    run_guards

    # luksFormat always needs one secret to start from. What that secret IS, and
    # whether it survives, is the whole difference between the three policies.
    if [ "$RECOVERY_KEY" = "1" ]; then
        # It stays in the header as the recovery keyslot, so it gets the
        # expensive KDF and has to reach a human before we go any further.
        ( umask 077; head -c 32 /dev/urandom | base32 | tr -d '\n' > "$RECOVERY_TMP" )
        boot_key="$RECOVERY_TMP"
        pbkdf=(--pbkdf argon2id
               --pbkdf-force-iterations "$PBKDF_ITER"
               --pbkdf-memory "$PBKDF_MEMORY"
               --pbkdf-parallel "$PBKDF_PARALLEL")
        trap 'print_recovery_key "PROVISIONING FAILED -- SAVE THIS KEY BEFORE REBOOT"' ERR
    elif [ "$KEY_MODE" = "keyfile" ]; then
        # data.key can open the container from the very first moment, so it is
        # the only keyslot that ever exists. No argon2id slot means no wasted
        # Argon2id attempt on every unlock either.
        [ -f "$KEYFILE" ] || die "keyfile $KEYFILE missing"
        boot_key="$KEYFILE"
        pbkdf=(--pbkdf pbkdf2 --pbkdf-force-iterations 1000)
    else
        # Transient: alive only between luksFormat and the TPM enrol, then removed.
        ( umask 077; head -c 32 /dev/urandom > "$BOOTSTRAP_TMP" )
        boot_key="$BOOTSTRAP_TMP"
        pbkdf=(--pbkdf pbkdf2 --pbkdf-force-iterations 1000)
        drop_boot=1
    fi

    # Label wip until done: "cannot open + label=wip" on next boot means safe to
    # rebuild; "label=ready" must never be erased.
    cryptsetup luksFormat --type luks2 --batch-mode \
        --label "$LABEL_WIP" \
        --key-file "$boot_key" \
        --cipher aes-xts-plain64 --key-size 512 --sector-size 4096 \
        "${pbkdf[@]}" \
        "$TARGET"
    log "luksFormat done, label=$LABEL_WIP"

    case "$KEY_MODE" in
        tpm)
            wait_for_dev /dev/tpmrm0 || die "/dev/tpmrm0 did not appear"
            # --tpm2-pcrs= must be explicit -- omitting it defaults to PCR 7, not
            # "none". No measured boot here, so binding PCRs would be a false assurance.
            systemd-cryptenroll --unlock-key-file="$boot_key" \
                --tpm2-device=auto --tpm2-pcrs= "$TARGET"
            log "TPM keyslot enrolled"
            ;;
        keyfile)
            # Already the format key unless a recovery key took that role.
            if [ "$boot_key" != "$KEYFILE" ]; then
                [ -f "$KEYFILE" ] || die "keyfile $KEYFILE missing"
                cryptsetup luksAddKey --batch-mode --key-file "$boot_key" \
                    --pbkdf pbkdf2 --pbkdf-force-iterations 1000 \
                    "$TARGET" "$KEYFILE"
                log "keyfile keyslot added"
            fi
            ;;
        *) die "unknown LUKS_DATA_KEY_MODE '$KEY_MODE'" ;;
    esac

    # Verify the real unlock path BEFORE dropping the bootstrap key.
    unlock

    if [ "$drop_boot" = "1" ]; then
        # Remove by keyfile, never by slot number -- slot order isn't fixed and
        # killing the wrong one is silent.
        cryptsetup luksRemoveKey "$TARGET" "$boot_key"
        log "bootstrap keyslot removed; the TPM is now the only way in"
    fi

    if [ "$RECOVERY_KEY" = "1" ]; then
        trap - ERR
        print_recovery_key "RECOVERY KEY -- shown ONCE, cannot be recovered"
    fi
    wipe_tmp_keys

    mkfs.ext4 -F -L cryptdata "/dev/mapper/$MAPPER"
    cryptsetup config --label "$LABEL_READY" "$TARGET"
    log "mkfs done, label=$LABEL_READY"

    mount_target
    log "provisioning done"
}

add_recovery_key() {
    cryptsetup isLuks --type luks2 "$TARGET" || die "$TARGET is not a LUKS2 volume"
    unlock
    case "$KEY_MODE" in
        tpm)
            # systemd-cryptenroll generates and prints its own recovery key.
            systemd-cryptenroll --unlock-tpm2-device=auto --recovery-key "$TARGET"
            ;;
        keyfile)
            [ -f "$KEYFILE" ] || die "keyfile $KEYFILE missing"
            ( umask 077; head -c 32 /dev/urandom | base32 | tr -d '\n' > "$RECOVERY_TMP" )
            cryptsetup luksAddKey --batch-mode --key-file "$KEYFILE" \
                --pbkdf argon2id \
                --pbkdf-force-iterations "$PBKDF_ITER" \
                --pbkdf-memory "$PBKDF_MEMORY" \
                --pbkdf-parallel "$PBKDF_PARALLEL" \
                "$TARGET" "$RECOVERY_TMP"
            print_recovery_key "RECOVERY KEY -- shown ONCE"
            wipe_tmp_keys
            ;;
        *) die "unknown LUKS_DATA_KEY_MODE '$KEY_MODE'" ;;
    esac
    log "recovery keyslot added"
}

# ---------------------------------------------------------------- main
main() {
    local do_provision=0 do_add_recovery=0 label

    case "${1:-}" in
        --provision)        do_provision=1 ;;
        --add-recovery-key) do_add_recovery=1 ;;
        "")                 do_provision="$AUTO_PROVISION" ;;
        *)                  die "unknown argument '$1' (use --provision or --add-recovery-key)" ;;
    esac

    resolve_target

    if ! wait_for_dev "$TARGET"; then
        echo "luks-data: FATAL: LUKS target not found: $DEV_SPEC (resolved to $TARGET)" >&2
        contract_table
        exit 1
    fi

    if [ "$do_add_recovery" = "1" ]; then
        add_recovery_key
        return 0
    fi

    # Already mounted -> nothing to do (service may be restarted).
    if mountpoint -q "$MOUNTPOINT"; then
        log "$MOUNTPOINT already mounted"
        return 0
    fi

    # Make sure the target is not a LUKS2 volume before trying to provision it.
    if ! cryptsetup isLuks --type luks2 "$TARGET"; then
        [ "$do_provision" = "1" ] || die "$TARGET is not provisioned yet. Run: ecu1270-luks-data.sh --provision"
        provision
        return 0
    fi

    # Read the label before unlocking: it is the only way to tell our own
    # half-built container from a finished one we merely cannot open.
    label="$(luks_label)"

    if ! unlock; then
        [ "$label" = "$LABEL_WIP" ] || \
            die "cannot open $TARGET and its label is '$label', not '$LABEL_WIP'. Refusing to touch it."
        [ "$do_provision" = "1" ] || \
            die "$TARGET is an unfinished container that cannot be opened. Run: ecu1270-luks-data.sh --provision"
        log "found our own unfinished container (label=$LABEL_WIP); it never held a filesystem, rebuilding"
        guard_not_rootfs
        dd if=/dev/zero of="$TARGET" bs=1M count="$HEADER_MIB" conv=fsync status=none
        provision
        return 0
    fi

    if [ -z "$(blkid -o value -s TYPE "/dev/mapper/$MAPPER" 2>/dev/null || true)" ]; then
        # luksFormat succeeded but mkfs never ran (power loss mid-provision) --
        # just finish the job; don't reformat or `cryptsetup erase`.
        [ "$label" = "$LABEL_WIP" ] || \
            die "no filesystem on /dev/mapper/$MAPPER but label is '$label', not '$LABEL_WIP'. Refusing to touch it."
        [ "$do_provision" = "1" ] || die "provisioning was interrupted. Run: ecu1270-luks-data.sh --provision"
        log "resuming interrupted provisioning (label=$LABEL_WIP)"
        mkfs.ext4 -F -L cryptdata "/dev/mapper/$MAPPER"
        cryptsetup config --label "$LABEL_READY" "$TARGET"
    fi

    mount_target
}

main "$@"