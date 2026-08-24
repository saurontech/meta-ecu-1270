# ═══════════════════════════════════════════════════════════════════
# ECU1270 data-partition LUKS encryption — single source of truth.
# Enable with LUKS_DATA_ENABLED = "1" in local.conf.
# ═══════════════════════════════════════════════════════════════════
LUKS_DATA_ENABLED  ?= "0"

# "tpm" unlocks via the on-board TPM, no key in the image.
# "keyfile" unlocks via /etc/ecu1270/data.key -- no security, key sits in plaintext rootfs.
LUKS_DATA_KEY_MODE ?= "tpm"

# Partition to encrypt, as "part:N" (N relative to the boot device resolved
# from /proc/cmdline root=). No default: it depends on which flags
# tools/flash/j722s-ecu1270_flash.sh was run with:
#   --rauc            -> part:4   (the layout we ship)
#   --appdata         -> part:3   (flash-tool stage B, not implemented yet)
#   --rauc --appdata  -> part:5   (needs GPT: MBR has only 4 primaries)
#   (--overlay-data does not affect the number)
# ECU-1270 has a FAT boot partition at p1: part:1 is boot (bricks the board),
# part:2 and part:3 are rootfs slot A and B when RAUC is on.
LUKS_DATA_DEVICE   ?= ""
LUKS_DATA_MAPPER   ?= "data"
# Set to "/data" explicitly in local.conf when LUKS_DATA_DEVICE is part:4 (RAUC on).
LUKS_DATA_MOUNT    ?= "/appdata"

# A recovery keyslot is a second way in, held by a human off-device.
# Add one later per-unit with: ecu1270-luks-data.sh --add-recovery-key
LUKS_DATA_RECOVERY_KEY ?= "0"

# Provision on first boot instead of requiring an explicit --provision run.
LUKS_DATA_AUTO_PROVISION ?= "1"

# Argon2id cost, pinned so it doesn't depend on which machine ran luksFormat.
# Re-measure with `cryptsetup benchmark` before changing -- requires temporarily
# uncommenting CONFIG_CRYPTO_USER_API_{SKCIPHER,HASH} in luks.cfg (off by default).
# 1048576 KiB = 1 GiB; halve it on the 2 GB DDR SKU to avoid OOM during provisioning.
LUKS_DATA_PBKDF_ITER     ?= "4"
LUKS_DATA_PBKDF_MEMORY   ?= "1048576"
LUKS_DATA_PBKDF_PARALLEL ?= "4"

# keyfile-mode key location on the build host.
# Create once: head -c 32 /dev/urandom > ~/.config/luks-keys-ecu1270/data.key
LUKS_DATA_KEYS_DIR ?= "${HOME}/.config/luks-keys-ecu1270"
LUKS_DATA_KEYFILE  ?= "${LUKS_DATA_KEYS_DIR}/data.key"

IMAGE_INSTALL:append = "${@' cryptsetup ecu1270-luks-data' \
    if d.getVar('LUKS_DATA_ENABLED') == '1' else ''}"

# Not packagegroup-security-tpm2: that pulls in TPM 1.2, the TPM simulator
# TCTI, tpm2-abrmd, pkcs11 and python bindings, none of which are needed.
# Requires meta-security/meta-tpm in bblayers.conf (Stage 2 only).
IMAGE_INSTALL:append = "${@' tpm2-tools tpm2-tss libtss2-tcti-device systemd-crypt' \
    if d.getVar('LUKS_DATA_ENABLED') == '1' \
    and d.getVar('LUKS_DATA_KEY_MODE') == 'tpm' else ''}"

# All three are required; none is in systemd's default PACKAGECONFIG:
#   cryptsetup -> systemd-cryptenroll binary
#   tpm2 -> links tpm2-tss so --tpm2-device works
#   cryptsetup-plugins -> the LUKS2 token plugin; without it `cryptsetup open`
#   silently ignores the TPM token
PACKAGECONFIG:append:pn-systemd = "${@' cryptsetup tpm2 cryptsetup-plugins' \
    if d.getVar('LUKS_DATA_ENABLED') == '1' \
    and d.getVar('LUKS_DATA_KEY_MODE') == 'tpm' else ''}"

python () {
    if d.getVar('LUKS_DATA_ENABLED') != '1':
        return

    mode = d.getVar('LUKS_DATA_KEY_MODE')
    if mode not in ('tpm', 'keyfile'):
        bb.fatal("LUKS_DATA_KEY_MODE must be 'tpm' or 'keyfile', got '%s'" % mode)

    dev = d.getVar('LUKS_DATA_DEVICE') or ''
    if not dev:
        bb.fatal("LUKS_DATA_DEVICE is not set. This has no safe default -- the\n"
                 "target partition depends on which flags\n"
                 "scripts/flash-sd/j722s-ecu1270_flash.sh was run with:\n"
                 "    --rauc            -> part:4   (the layout we ship)\n"
                 "    --appdata         -> part:3\n"
                 "    --rauc --appdata  -> part:5   (needs GPT)\n"
                 "Get this wrong and nothing will catch it: an empty partition\n"
                 "looks the same whether it's blank by design or blank because\n"
                 "you named the wrong one, so it gets silently formatted and\n"
                 "encrypted in place of the partition you actually meant.")
    if not dev.startswith('part:') or not dev[5:].isdigit():
        bb.fatal("LUKS_DATA_DEVICE must be 'part:N', got '%s'" % dev)

    n = int(dev[5:])
    rauc = d.getVar('RAUC_ENABLED') == '1'

    # p1 is always the FAT boot partition; it's not root=, so the runtime guard misses it.
    if n == 1:
        bb.fatal("LUKS_DATA_DEVICE = 'part:1' is the FAT boot partition on\n"
                 "ECU-1270 (tiboot3.bin / uboot.env). Encrypting it bricks the\n"
                 "board. Validated targets are part:3 (no RAUC) or part:4 (RAUC).")
    # p2 is always the rootfs (slot A when RAUC is on).
    if n == 2:
        bb.fatal("LUKS_DATA_DEVICE = 'part:2' is the rootfs on ECU-1270 "
                 "(slot A when RAUC is on). This design unlocks from userspace "
                 "in the real rootfs, so the rootfs itself can never be the "
                 "target. Validated targets are part:3 (no RAUC) or part:4 (RAUC).")
    # p3 is rootfs slot B with RAUC on. root= only names the current slot, and a
    # freshly flashed slot B is empty, so the emptiness guards would miss it too.
    if rauc and n == 3:
        bb.fatal("LUKS_DATA_DEVICE = 'part:3' is rootfs slot B on ECU-1270 when\n"
                 "RAUC is enabled (p2 = rootfs0/A, p3 = rootfs1/B). Encrypting a\n"
                 "slot breaks OTA with no symptom at boot.\n"
                 "Use part:4 with RAUC on, or part:3 only with RAUC off.")

    mnt = d.getVar('LUKS_DATA_MOUNT')

    # rauc-setup-env.sh hardcodes p4 -> /data, so with RAUC on these two must agree.
    if rauc and (n == 4) != (mnt == '/data'):
        bb.fatal("RAUC + LUKS mismatch: got LUKS_DATA_DEVICE='%s' with\n"
                 "LUKS_DATA_MOUNT='%s'. rauc-setup-env.sh always mounts p4 at\n"
                 "/data, so those two settings must agree. Decide which one you\n"
                 "actually want:\n"
                 "  (a) encrypt RAUC's own data partition (what we ship, and the\n"
                 "      only option MBR fits):\n"
                 "        LUKS_DATA_DEVICE = \"part:4\"\n"
                 "        LUKS_DATA_MOUNT  = \"/data\"\n"
                 "  (b) encrypt a SEPARATE partition (needs an extra appdata\n"
                 "      partition, which needs GPT on this board):\n"
                 "        LUKS_DATA_DEVICE = \"part:N\"   (N != 4)\n"
                 "        LUKS_DATA_MOUNT  = \"/appdata\"" % (dev, mnt))

    # Anything else is legal but unverified -- MBR only holds 4 primaries; see
    # the flash plan for how integrators can design their own layout.
    validated = (not rauc and n == 3) or (rauc and n == 4 and mnt == '/data')
    if not validated:
        bb.warn("LUKS_DATA_DEVICE='%s' / LUKS_DATA_MOUNT='%s' / RAUC_ENABLED='%s' "
                "is OUTSIDE the two validated combinations:\n"
                "  RAUC_ENABLED='0' -> LUKS_DATA_DEVICE='part:3', LUKS_DATA_MOUNT='/appdata'\n"
                "  RAUC_ENABLED='1' -> LUKS_DATA_DEVICE='part:4', LUKS_DATA_MOUNT='/data'\n"
                "This is not blocked, but you are responsible for the partition\n"
                "layout, the MBR 4-primary budget, and matching flash-tool flags."
                % (dev, mnt, d.getVar('RAUC_ENABLED')))

    rec  = d.getVar('LUKS_DATA_RECOVERY_KEY')
    auto = d.getVar('LUKS_DATA_AUTO_PROVISION')
    for name, val in (('LUKS_DATA_RECOVERY_KEY', rec),
                      ('LUKS_DATA_AUTO_PROVISION', auto)):
        if val not in ('0', '1'):
            bb.fatal("%s must be '0' or '1', got '%s'" % (name, val))
    # The recovery key is printed once on the console; nobody watches an
    # unattended first boot, so the two settings cannot both be on.
    if rec == '1' and auto == '1':
        bb.fatal("LUKS_DATA_RECOVERY_KEY='1' requires LUKS_DATA_AUTO_PROVISION='0'.\n"
                 "The recovery key is printed once and is unrecoverable afterwards,\n"
                 "so something has to be there to capture it. Provision those units\n"
                 "by hand:  ecu1270-luks-data.sh --provision\n"
                 "Or keep auto-provisioning and add a keyslot per unit later:\n"
                 "          ecu1270-luks-data.sh --add-recovery-key")

    for name in ('LUKS_DATA_PBKDF_ITER', 'LUKS_DATA_PBKDF_MEMORY',
                 'LUKS_DATA_PBKDF_PARALLEL'):
        val = d.getVar(name) or ''
        if not val.isdigit() or int(val) < 1:
            bb.fatal("%s must be a positive integer, got '%s'" % (name, val))

    if mode == 'keyfile':
        kf = d.getVar('LUKS_DATA_KEYFILE') or ''
        kd = d.getVar('LUKS_DATA_KEYS_DIR') or ''
        if not os.path.isfile(kf):
            bb.fatal("LUKS_DATA_KEYFILE (%s) not found. Create it once:\n"
                     "  mkdir -p %s && chmod 700 %s\n"
                     "  head -c 32 /dev/urandom > %s && chmod 400 %s\n"
                     "Do NOT commit it to the layer." % (kf, kd, kd, kf, kf))
}