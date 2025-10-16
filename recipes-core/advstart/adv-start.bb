SUMMARY = "Advantech start script"
LICENSE = "GPL-2.0-or-later"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/GPL-2.0-or-later;md5=fed54355545ffd980b814dab4a3b312c"

ADDON_FILES_DIR:="${THISDIR}/files"

inherit systemd
RDEPENDS:${PN} += "bash"

SRC_URI = "file://adv_rauc_start.sh \
           file://adv_rauc_start.service \
          "

SYSTEMD_SERVICE:${PN} = "adv_rauc_start.service"

do_install() {
        install -d ${D}${bindir}
        install -m 0755 ${ADDON_FILES_DIR}/adv_rauc_start.sh ${D}${bindir}/adv_rauc_start.sh

        install -d ${D}${systemd_unitdir}/system
        install -m 0644 ${ADDON_FILES_DIR}/adv_rauc_start.service ${D}${systemd_unitdir}/system/

}

FILES:${PN} += "${systemd_unitdir}/system/adv_rauc_start.service"


