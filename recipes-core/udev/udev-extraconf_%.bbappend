# Keep udev's automounter away from the RAUC A/B slots.
#
# We use the drop-in directory upstream already reads:
# mount.sh consults /etc/udev/mount.ignorelist and
# /etc/udev/mount.ignorelist.d/* before mounting anything.
#
# Gated on RAUC_ENABLED so a non-RAUC build behaves exactly as before
# (see conf/include/j722s-ecu1270-rauc.inc).

FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI += "${@' file://rauc-slots.ignorelist' if d.getVar('RAUC_ENABLED') == '1' else ''}"

# RAUC_ENABLED is set per-machine, so the resulting package is machine-specific.
PACKAGE_ARCH = "${MACHINE_ARCH}"

do_install:append() {
    if [ "${RAUC_ENABLED}" = "1" ]; then
        install -d ${D}${sysconfdir}/udev/mount.ignorelist.d
        install -m 0644 ${WORKDIR}/rauc-slots.ignorelist \
            ${D}${sysconfdir}/udev/mount.ignorelist.d/rauc-slots.ignorelist
    fi
}
