FILESEXTRAPATHS:prepend := "${THISDIR}/files:"


#SRC_URI += " \
#	file://0001-add-driver-support-for-cooling-device.patch \
#	file://0002-modify-dts-for-k3-cooling.patch \
#	file://0003-add-ecu1270-dts.patch \
#"
#SRC_URI:append:j722s-ecu1270 = " file://0001-add-driver-support-for-cooling-device.patch"
#SRC_URI:append:j722s-ecu1270 = " file://0002-modify-dts-for-k3-cooling.patch"
#SRC_URI:append:j722s-ecu1270 = " file://0003-add-ecu1270-dts.patch"
SRC_URI:append:j722s-ecu1270 = " file://0001-add-dts-for-ecu-1270-ES2-hardware.patch"

SRC_URI:append:j722s-ecu1270 = " file://rauc.cfg"


KERNEL_CONFIG_FRAGMENTS += " ${WORKDIR}/rauc.cfg"

#do_configure:append() {
#    cp ${WORKDIR}/${ADV_ECU_FOLDER}/k3-j722s-ecu*.dts ${S}/arch/arm64/boot/dts/ti/ 
#    cp ${WORKDIR}/${ADV_ECU_FOLDER}/qmi_wwan_q.c ${S}/drivers/net/usb/qmi_wwan_q.c
#    cp ${WORKDIR}/${ADV_ECU_FOLDER}/adv_board.c ${S}/drivers/char/adv_board.c
#    cp ${WORKDIR}/${ADV_ECU_FOLDER}/board-name.h ${S}/drivers/char/board-name.h
#    cp ${WORKDIR}/${ADV_ECU_FOLDER}/k3-j722s-ecu*.dts ${S}/scripts/dtc/include-prefixes/arm64/ti/
#   
#}

#do_configure:prepend(){
#    cp ${WORKDIR}/k3-j722s_ECU1270_defconfig ${S}/arch/arm64/configs/k3-j722s_ECU1270_defconfig
#    cp ${WORKDIR}/ecu1270.cfg ${B}/ecu1270.cfg
#}

