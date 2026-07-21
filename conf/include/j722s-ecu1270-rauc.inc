# j722s-ecu1270-rauc.inc — Single source of truth for ECU1270 RAUC policy.
# Everything RAUC-related is gated behind two boolean toggles so the layer
# behaves exactly like "no RAUC" when disabled (safe to keep resident).

RAUC_ENABLED ?= "0"
RAUC_ADAPTIVE_ENABLED ?= "0"

RAUC_SYSTEM_COMPATIBLE ?= "j722s-ecu1270"

# RAUC OTA bundle format and rootfs alignment are conditional on the adaptive toggle.
IMAGE_FSTYPES:append = "${@' ext4' if d.getVar('RAUC_ENABLED') == '1' else ''}"

# Adaptive (block-hash-index) mandates verity; plain cannot be block-verified.
RAUC_BUNDLE_FORMAT ?= "${@'verity' if d.getVar('RAUC_ADAPTIVE_ENABLED') == '1' else 'plain'}"

# 4 KiB alignment keeps block-hash-index hit-rate stable when adaptive is on.
IMAGE_ROOTFS_ALIGNMENT = "${@'4' if d.getVar('RAUC_ADAPTIVE_ENABLED') == '1' else '1'}"

# Conditional integration — only when explicitly enabled.
DISTRO_FEATURES:append = "${@' rauc' if d.getVar('RAUC_ENABLED') == '1' else ''}"
IMAGE_INSTALL:append   = "${@' rauc rauc-conf libubootenv-bin' if d.getVar('RAUC_ENABLED') == '1' else ''}"

# Prerequisite guard: adaptive requires the master switch.
python () {
    if d.getVar('RAUC_ADAPTIVE_ENABLED') == '1' and d.getVar('RAUC_ENABLED') != '1':
        bb.fatal("RAUC_ADAPTIVE_ENABLED=1 requires RAUC_ENABLED=1")
}