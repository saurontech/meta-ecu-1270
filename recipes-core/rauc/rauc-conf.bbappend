FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
ADDON_FILES_DIR:="${THISDIR}/files"


do_install:append () {
	install -d ${DEPLOY_DIR_IMAGE}

        install -m 0644 ${ADDON_FILES_DIR}/ca.cert.pem ${DEPLOY_DIR_IMAGE}/
        install -m 0644 ${ADDON_FILES_DIR}/key.pem ${DEPLOY_DIR_IMAGE}/
        install -m 0644 ${ADDON_FILES_DIR}/system.conf ${DEPLOY_DIR_IMAGE}/


	install -m 0644 ${ADDON_FILES_DIR}/system.conf ${D}${sysconfdir}/rauc/
	install -m 0644 ${ADDON_FILES_DIR}/system_sd.conf ${D}${sysconfdir}/rauc/
        install -m 0644 ${ADDON_FILES_DIR}/system_emmc.conf ${D}${sysconfdir}/rauc/
        install -m 0644 ${ADDON_FILES_DIR}/ca.cert.pem ${D}${sysconfdir}/rauc/

}


