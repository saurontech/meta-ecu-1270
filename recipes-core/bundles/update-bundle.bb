SUMMARY = "ECU1270 RAUC update bundle (rootfs only, v1)"
LICENSE = "MIT"

inherit bundle

RAUC_BUNDLE_COMPATIBLE  = "${RAUC_SYSTEM_COMPATIBLE}"
RAUC_BUNDLE_VERSION     = "${DATETIME}"
RAUC_BUNDLE_VERSION[vardepsexclude] = "DATETIME"
RAUC_BUNDLE_DESCRIPTION = "ECU1270 rootfs update"

RAUC_BUNDLE_SLOTS = "rootfs"
# ECU1270 image recipe (per flash-sd scripts: tisdk-base-image-j722s-ecu1270).
RAUC_SLOT_rootfs  = "tisdk-base-image"
RAUC_SLOT_rootfs[fstype] = "ext4"

# When adaptive is enabled, tag the rootfs slot with the block-hash-index method.
# (RAUC_BUNDLE_FORMAT is DERIVED in ecu1270-rauc.inc, §2.1 — not set here.)
python () {
    if d.getVar('RAUC_ADAPTIVE_ENABLED') == '1':
        d.setVarFlag('RAUC_SLOT_rootfs', 'adaptive', 'block-hash-index')

    if d.getVar('RAUC_ADAPTIVE_ENABLED') == '1' and d.getVar('RAUC_BUNDLE_FORMAT') == 'plain':
        bb.fatal("RAUC_ADAPTIVE_ENABLED=1 is incompatible with RAUC_BUNDLE_FORMAT=plain (need verity) for %s" % d.getVar('PN'))
}

# Signing key default paths (physical isolation: private keys live OUTSIDE
# this layer, never committed). Override in local.conf for CI / HSM.
RAUC_KEYS_DIR     ?= "${HOME}/.config/rauc-keys-ecu1270"
RAUC_KEY_FILE     ?= "${RAUC_KEYS_DIR}/dev.key.pem"
RAUC_CERT_FILE    ?= "${RAUC_KEYS_DIR}/dev.cert.pem"
RAUC_KEYRING_FILE ?= "${RAUC_KEYS_DIR}/ca.cert.pem"