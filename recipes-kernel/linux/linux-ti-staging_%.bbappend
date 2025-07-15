FILESEXTRAPATHS:prepend := "${THISDIR}/files:"


ADV_ECU_FOLDER = "adv_ecu"

SRC_URI += "\
    file://${ADV_ECU_FOLDER} \
    file://0001-j722s-evm-board-basic.patch \
    file://0002-j722s-evm-board-others.patch \
    file://k3-j722s_ECU1270_defconfig \
    file://ecu1270.cfg \
"

#file://test_adv7511_drv.patch

KERNEL_CONFIG_FRAGMENTS += "ecu1270.cfg"

do_configure:append() {
    cp ${WORKDIR}/${ADV_ECU_FOLDER}/k3-j722s-ecu*.dts ${S}/arch/arm64/boot/dts/ti/ 
    cp ${WORKDIR}/${ADV_ECU_FOLDER}/qmi_wwan_q.c ${S}/drivers/net/usb/qmi_wwan_q.c
    cp ${WORKDIR}/${ADV_ECU_FOLDER}/adv_board.c ${S}/drivers/char/adv_board.c
    cp ${WORKDIR}/${ADV_ECU_FOLDER}/board-name.h ${S}/drivers/char/board-name.h
    cp ${WORKDIR}/${ADV_ECU_FOLDER}/k3-j722s-ecu*.dts ${S}/scripts/dtc/include-prefixes/arm64/ti/
   
}

do_configure:prepend(){
    cp ${WORKDIR}/k3-j722s_ECU1270_defconfig ${S}/arch/arm64/configs/k3-j722s_ECU1270_defconfig
    cp ${WORKDIR}/ecu1270.cfg ${B}/ecu1270.cfg
}

# 
# cp ${WORKDIR}/ecu1270.cfg ${S}/arch/arm64/configs/ecu1270.cfg
# cp ${WORKDIR}/${ADV_ECU_FOLDER}/mydefconfig ${WORKDIR}/defconfig
