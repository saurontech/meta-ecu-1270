FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

inherit systemd

python () {
    if d.getVar('RAUC_ENABLED') != '1':
        raise bb.parse.SkipRecipe("RAUC disabled (RAUC_ENABLED != 1)")
}

SRC_URI += " \
    file://rauc-setup-env.sh \
    file://rauc-setup-env.service \
"

# lsblk / mountpoint for boot-device detection at runtime.
RDEPENDS:${PN} += "util-linux-lsblk util-linux-mountpoint"

SYSTEMD_SERVICE:${PN} = "rauc-setup-env.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

# Values baked into the setup script (sourced from the SSOT include, §2.1).
RAUC_SYSTEM_COMPATIBLE ?= "ecu1270"
RAUC_BUNDLE_FORMAT ?= "plain"

do_install:append() {
    # Keyring: public CA only — never the signing private key.
    install -d ${D}${sysconfdir}/rauc
    install -m 0644 ${WORKDIR}/ca.cert.pem ${D}${sysconfdir}/rauc/

    # Placeholder system.conf — real content generated at boot by the service.
    echo "# Placeholder - generated at boot by rauc-setup-env.service" \
        > ${D}${sysconfdir}/rauc/system.conf

    # Setup script: bake compatible + bundle format into the heredoc placeholders.
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/rauc-setup-env.sh ${D}${bindir}/rauc-setup-env.sh
    sed -i \
        -e 's/@RAUC_SYSTEM_COMPATIBLE@/${RAUC_SYSTEM_COMPATIBLE}/g' \
        -e 's/@RAUC_BUNDLE_FORMATS@/${RAUC_BUNDLE_FORMAT}/g' \
        ${D}${bindir}/rauc-setup-env.sh

    # systemd unit (Before=rauc.service).
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/rauc-setup-env.service ${D}${systemd_system_unitdir}/

    # Persistent mountpoint.
    install -d ${D}/data
}

FILES:${PN} += "${systemd_system_unitdir}/rauc-setup-env.service ${sysconfdir}/rauc/system.conf /data"
