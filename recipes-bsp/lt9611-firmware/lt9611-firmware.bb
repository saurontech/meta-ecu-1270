SUMMARY = "Firmware for Lontium LT9611UXD HDMI Bridge"
LICENSE = "CLOSED"

SRC_URI = "file://LT9611UXD.bin"

do_install() {
    install -d ${D}${base_libdir}/firmware
    install -m 0644 ${WORKDIR}/LT9611UXD.bin ${D}${base_libdir}/firmware/
}

FILES:${PN} = "${base_libdir}/firmware/LT9611UXD.bin"