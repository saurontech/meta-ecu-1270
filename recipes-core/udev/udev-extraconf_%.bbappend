# Keep udev's automounter away from the on-board eMMC and SD slot.
#
# Unconditional on purpose. "The on-board eMMC and the SD slot are the media
# we boot and OTA from, so they must not be automounted" is true regardless of
# whether RAUC / LUKS / overlay-root are enabled

FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI += " file://ecu1270-internal-storage.ignorelist"

PACKAGE_ARCH = "${MACHINE_ARCH}"

do_install:append() {
    install -d ${D}${sysconfdir}/udev/mount.ignorelist.d
    install -m 0644 ${WORKDIR}/ecu1270-internal-storage.ignorelist \
        ${D}${sysconfdir}/udev/mount.ignorelist.d/ecu1270-internal-storage.ignorelist
}
