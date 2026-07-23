# `j722s-ecu1270_flash.sh` — SD / eMMC flashing tool

Flash an SD card or eMMC for the **Advantech ECU-1270** (TI J722S).

A single script covers every layout combination currently supported by
`meta-ecu-1270`:

- **Rootfs base**: pure Yocto rootfs, or an external Ubuntu/Debian rootfs with the
  Yocto kernel modules / firmware overlaid on top.
- **Boot mode**: plain single-rootfs, or RAUC A/B (`--rauc`).
- **Secure boot**: HS-FS (field-securable, default) or HS-SE (`--hs-se`, production
  locked boards) `tiboot3` variant.

> [!NOTE]
> The script also accepts `-O, --overlay-data`, which adds a trailing ext4
> partition for a persistent overlayfs upper/work dir. This is plumbing for a
> future immutable/read-only-root feature that is **not yet enabled** in
> `meta-ecu-1270`, so it is intentionally left out of the scenarios below.

TI J722S uses a **separate FAT16 boot partition** (`p1`) holding the
three-stage K3 boot chain as individual files:

```
tiboot3.bin  — R5 first-stage (DMSC + System Firmware; HS-FS or HS-SE)
tispl.bin    — A53 SPL (TF-A + OP-TEE + DDR init)
u-boot.img   — U-Boot proper
```

The kernel + device tree are bundled into a signed FIT image (`fitImage`),
which lives in the active rootfs at `/boot/fitImage` and is loaded by U-Boot
via `ext4load` — there is no separate `Image` + `.dtb` pair to copy onto the
boot partition.

> [!CAUTION]
> The script **wipes the entire target disk**. Double-check `--disk` before running.

---

## Prerequisites

### Host tools

```console
foo@bar:~$ sudo apt-get install parted e2fsprogs zstd
```

`sudo` is required (the script re-execs itself through `sudo` if needed).

### Build artifacts

Build the image first (see the top-level `meta-ecu-1270` `README.md`). All
artifacts live in the deploy directory, which is passed once via `--images`:

```
build/deploy-ti/images/j722s-ecu1270/
├── tisdk-base-image-j722s-ecu1270.rootfs.tar.xz   # Yocto rootfs (always required)
├── tiboot3-j722s-hs-fs-evm.bin                     # R5 first-stage (HS-FS, default)
├── tiboot3-j722s-hs-evm.bin                        # R5 first-stage (HS-SE, --hs-se)
├── tispl.bin-j722s-ecu1270-*                        # A53 SPL (auto-detected)
├── u-boot-j722s-ecu1270-*.img                       # U-Boot proper (auto-detected)
├── fitImage--*-j722s-ecu1270*.bin                   # signed kernel+dtb FIT (auto-detected)
└── update-bundle-j722s-ecu1270.raucb                # RAUC bundle (only if built; see --bundle)
```

The external **Ubuntu/Debian** rootfs tarball (e.g.
`ubuntu-24.04-arm64-generic.rootfs.tar.zst`) is **not** produced by Yocto —
build it separately (see [`DebianRootfsOnTiYocto_en.md`](../DebianRootfsOnTiYocto_en.md))
and pass it with `--ubuntu`.

---

## Option quick reference

| Option | Meaning |
| --- | --- |
| `-d, --disk <dev>` | Target block device (e.g. `/dev/sdb`, `/dev/mmcblk0`). Prompts if omitted. |
| `-i, --images <dir>` | Folder to resolve bare artifact names (the deploy dir). |
| `--yocto, --bsp <file>` | Yocto rootfs tarball. **Always required** (modules/firmware source; also the rootfs base when `--ubuntu` is omitted). |
| `--ubuntu <file>` | External Ubuntu/Debian rootfs tarball. Optional base. |
| `--tiboot3 <file>` | R5 first-stage (default: auto-detect `tiboot3-j722s-hs-fs-evm.bin`, or the HS-SE variant with `--hs-se`). |
| `--tispl <file>` | A53 SPL (default: auto-detect `tispl.bin-j722s-ecu1270-*`). |
| `--uboot-img <file>` | U-Boot proper (default: auto-detect `u-boot-j722s-ecu1270-*.img`). |
| `-f, --fitimage <file>` | Signed kernel+dtb FIT image, installed as rootfs `/boot/fitImage` (default: auto-detect `fitImage--*-j722s-ecu1270*`). |
| `--bundle <file>` | `*.raucb` to pre-stage on `/data` (`--rauc` only, optional). |
| `--hs-se` | Use the HS-SE `tiboot3` variant for production-locked boards. |
| `-R, --rauc` | RAUC A/B layout (`p1` boot, `p2` rootfs A, `p3` rootfs B, `p4` `/data`). |
| `--boot-size <sz>` | FAT boot partition size (default `128MiB`). |
| `--rootfs-size <sz>` | Size of each rootfs partition (default `5GiB`). |
| `--data-size <sz>` | RAUC `/data` partition size (default `15GiB` — sized for the RAUC adaptive-update block-hash cache). |
| `-y, --yes` | Skip the confirmation prompt. |
| `-h, --help` | Full help, including the partition design. |

Bare names (e.g. `tispl.bin-j722s-ecu1270-*`) are resolved inside `--images`;
absolute / relative paths are also accepted and take priority.

---

## Step 0 — Identify the target disk

```console
foo@bar:~$ lsblk -d -p -o NAME,SIZE,MODEL,TRAN | grep -E 'usb|mmc'
```

Pick the SD card / eMMC node (e.g. `/dev/sdb`). On the target, the on-board
eMMC is always `mmcblk0` and the SD slot is always `mmcblk1`.

In every example below, `$IMAGES_DIR` is the deploy directory:

```console
foo@bar:~/yocto$ IMAGES_DIR=build/deploy-ti/images/j722s-ecu1270
```

---

## Scenario 1 — Yocto rootfs (plain, non-RAUC, default)

Pure Yocto rootfs, HS-FS secure boot (default), single partition.

```
p1  FAT16  boot (128 MiB)  tiboot3.bin, tispl.bin, u-boot.img
p2  ext4   rootfs          (/boot/fitImage lives here)
```

```console
foo@bar:~/yocto$ sudo ./tools/flash/j722s-ecu1270_flash.sh \
    --disk   /dev/sdX \
    --images "$IMAGES_DIR" \
    --yocto  tisdk-base-image-j722s-ecu1270.rootfs.tar.xz
```

All boot artifacts (`tiboot3`, `tispl`, `u-boot.img`, `fitImage`) are
auto-detected from `--images`.

---

## Scenario 2 — Ubuntu + Yocto modules (non-RAUC)

External Ubuntu/Debian base + Yocto kernel modules / firmware overlaid on
top; `fitImage` still comes from the Yocto side (`--images` or `--fitimage`).

```console
foo@bar:~/yocto$ sudo ./tools/flash/j722s-ecu1270_flash.sh \
    --disk   /dev/sdX \
    --images "$IMAGES_DIR" \
    --ubuntu ubuntu-24.04-arm64-generic.rootfs.tar.zst \
    --yocto  tisdk-base-image-j722s-ecu1270.rootfs.tar.xz
```

---

## Scenario 3 — Yocto rootfs + RAUC A/B

RAUC A/B layout, plain rootfs. Slot A is flashed; slot B is left empty for
the first OTA install; `/data` holds RAUC status and the adaptive-update
block-hash cache.

```
p1  FAT16  boot (128 MiB)  tiboot3.bin, tispl.bin, u-boot.img
p2  ext4   rootfs A   (flashed)
p3  ext4   rootfs B   (empty; populated by 'rauc install')
p4  ext4   /data      (RAUC status + adaptive-update cache)
```

```console
foo@bar:~/yocto$ sudo ./tools/flash/j722s-ecu1270_flash.sh \
    --disk   /dev/sdX \
    --images "$IMAGES_DIR" \
    --rauc \
    --yocto  tisdk-base-image-j722s-ecu1270.rootfs.tar.xz
```

After first boot, verify with `lsblk` (expect `mmcblk1p1/p2/p3/p4`),
`findmnt /` (expect `/dev/mmcblk1p2`), and `rauc status`. For the full OTA
flow see the top-level `meta-ecu-1270` `README.md`, "RAUC OTA (A/B update)"
section.

---

## Scenario 4 — Yocto rootfs + RAUC A/B + pre-staged bundle

Same as Scenario 3, but also copies a signed `.raucb` bundle onto `/data` so
the first OTA install doesn't require a separate `scp`.

```console
foo@bar:~/yocto$ sudo ./tools/flash/j722s-ecu1270_flash.sh \
    --disk   /dev/sdX \
    --images "$IMAGES_DIR" \
    --rauc \
    --yocto  tisdk-base-image-j722s-ecu1270.rootfs.tar.xz \
    --bundle update-bundle-j722s-ecu1270.raucb
```

On the target:

```console
root@j722s-ecu1270:~$ rauc install /data/update-bundle-j722s-ecu1270.raucb
```

---

## Scenario 5 — HS-SE secure boot (production-locked boards)

`--hs-se` switches the auto-detected `tiboot3` from the HS-FS default
(`tiboot3-j722s-hs-fs-evm.bin`) to the HS-SE variant
(`tiboot3-j722s-hs-evm.bin`) required by boards that have already been fused
to High Security via the OTP keywriter procedure. Combine with `--rauc` as
needed; the partition layout is unaffected.

```console
foo@bar:~/yocto$ sudo ./tools/flash/j722s-ecu1270_flash.sh \
    --disk   /dev/sdX \
    --images "$IMAGES_DIR" \
    --hs-se \
    --rauc \
    --yocto  tisdk-base-image-j722s-ecu1270.rootfs.tar.xz
```

---

## Scenario matrix

| # | Scenario | `--ubuntu` | `--rauc` | `--bundle` | `--hs-se` | Partitions |
| --- | --- | :---: | :---: | :---: | :---: | --- |
| 1 | Yocto (plain) | | | | | `p1 p2` |
| 2 | Ubuntu + Yocto modules | yes | | | | `p1 p2` |
| 3 | Yocto + RAUC | | yes | | | `p1 p2 p3 p4` |
| 4 | Yocto + RAUC + bundle | | yes | yes | | `p1 p2 p3 p4` |
| 5 | HS-SE (+ RAUC) | | optional | | yes | `p1 p2` or `p1 p2 p3 p4` |

`--yocto/--bsp <rootfs tarball>` is required in **all** scenarios (it
provides the kernel modules / firmware, and is the rootfs base whenever
`--ubuntu` is omitted).

---

## After flashing

Remove the card, insert it into the ECU-1270, and power on.

- **All scenarios** — confirm the boot chain and active rootfs:

  ```console
  root@j722s-ecu1270:~$ lsblk                       # expect mmcblk1p1(/p2[/p3/p4])
  root@j722s-ecu1270:~$ findmnt /                    # active rootfs partition
  ```

- **RAUC scenarios** — confirm the A/B layout and status:

  ```console
  root@j722s-ecu1270:~$ rauc status                 # booted from system0/A, slot B empty
  root@j722s-ecu1270:~$ fw_printenv BOOT_ORDER       # current slot boot order
  ```

- **HS-SE scenarios** — remember that a `tiboot3.bin` built for OTP
  keywriting is *not* the one used at runtime; make sure the boot partition
  ends up with the HS-SE `tiboot3-j722s-hs-evm.bin` produced by the normal
  Yocto build (this script does that automatically with `--hs-se`).

For the full RAUC OTA and RAUC Adaptive Update workflows, see the top-level
`meta-ecu-1270` `README.md`.
