SUMMARY = "Unlock the encrypted data partition (and provision it on demand)"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit systemd

SRC_URI = " \
    file://ecu1270-luks-data.sh \
    file://ecu1270-luks-data.service \
    file://rauc-setup-env.service.d/10-luks-data.conf \
"

S = "${WORKDIR}"

SYSTEMD_SERVICE:${PN}     = "ecu1270-luks-data.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

RDEPENDS:${PN} = " \
    bash cryptsetup e2fsprogs-mke2fs \
    util-linux-blkid util-linux-lsblk util-linux-mount util-linux-mountpoint \
"
RDEPENDS:${PN} += "${@' systemd-crypt tpm2-tools' \
    if d.getVar('LUKS_DATA_KEY_MODE') == 'tpm' else ''}"

# Content depends on machine-level LUKS_* / RAUC_ENABLED.
PACKAGE_ARCH = "${MACHINE_ARCH}"

python () {
    if d.getVar('LUKS_DATA_ENABLED') != '1':
        raise bb.parse.SkipRecipe("LUKS disabled (LUKS_DATA_ENABLED != 1)")
}

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/ecu1270-luks-data.sh ${D}${bindir}/

    sed -i \
        -e "s|@LUKS_DATA_KEY_MODE@|${LUKS_DATA_KEY_MODE}|g" \
        -e "s|@LUKS_DATA_DEVICE@|${LUKS_DATA_DEVICE}|g" \
        -e "s|@LUKS_DATA_MAPPER@|${LUKS_DATA_MAPPER}|g" \
        -e "s|@LUKS_DATA_MOUNT@|${LUKS_DATA_MOUNT}|g" \
        -e "s|@LUKS_DATA_RECOVERY_KEY@|${LUKS_DATA_RECOVERY_KEY}|g" \
        -e "s|@LUKS_DATA_AUTO_PROVISION@|${LUKS_DATA_AUTO_PROVISION}|g" \
        -e "s|@LUKS_DATA_PBKDF_ITER@|${LUKS_DATA_PBKDF_ITER}|g" \
        -e "s|@LUKS_DATA_PBKDF_MEMORY@|${LUKS_DATA_PBKDF_MEMORY}|g" \
        -e "s|@LUKS_DATA_PBKDF_PARALLEL@|${LUKS_DATA_PBKDF_PARALLEL}|g" \
        -e "s|@RAUC_ENABLED@|${RAUC_ENABLED}|g" \
        ${D}${bindir}/ecu1270-luks-data.sh

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/ecu1270-luks-data.service ${D}${systemd_system_unitdir}/

    install -d ${D}${LUKS_DATA_MOUNT}

    # data.key only exists in keyfile mode. Source is the build host path in
    # LUKS_DATA_KEYFILE, NOT SRC_URI (never commit a key to the layer).
    if [ "${LUKS_DATA_KEY_MODE}" = "keyfile" ]; then
        install -d -m 0700 ${D}${sysconfdir}/ecu1270
        install -m 0400 "${LUKS_DATA_KEYFILE}" ${D}${sysconfdir}/ecu1270/data.key
    fi

    # The ONLY place that mentions both LUKS and RAUC. Scheme A only.
    if [ "${RAUC_ENABLED}" = "1" ] && [ "${LUKS_DATA_MOUNT}" = "/data" ]; then
        install -d ${D}${systemd_system_unitdir}/rauc-setup-env.service.d
        install -m 0644 ${WORKDIR}/rauc-setup-env.service.d/10-luks-data.conf \
            ${D}${systemd_system_unitdir}/rauc-setup-env.service.d/
    fi
}

FILES:${PN} += " \
    ${systemd_system_unitdir}/ecu1270-luks-data.service \
    ${systemd_system_unitdir}/rauc-setup-env.service.d \
    ${LUKS_DATA_MOUNT} \
"
FILES:${PN} += "${@' ${sysconfdir}/ecu1270' \
    if d.getVar('LUKS_DATA_KEY_MODE') == 'keyfile' else ''}"

# Without this, sstate cannot see that data.key changed and silently reuses the
# previously packaged one.
do_install[file-checksums] += "${@'%s:True' % d.getVar('LUKS_DATA_KEYFILE') \
    if d.getVar('LUKS_DATA_KEY_MODE') == 'keyfile' else ''}"