FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += " \
	file://j722s-ecu1270 \
"

SRC_URI:append:j722s-ecu1270 = " file://0001-u-boot-ti-base-modify.patch"

do_configure:prepend() {
	cp ${WORKDIR}/j722s-ecu1270/arch/arm/dts/k3-j722s-ecu1270.dts ${S}/arch/arm/dts/k3-j722s-evm.dts
	cp -f ${WORKDIR}/j722s-ecu1270/configs/j722s_ecu1270_a53_defconfig ${S}/configs/j722s_evm_a53_defconfig
	
	cp -f ${S}/include/configs/j722s_evm.h ${S}/include/configs/j722s_evm.h_bak
	cp -f ${WORKDIR}/j722s-ecu1270/include/configs/j722s_adv.h ${S}/include/configs/j722s_evm.h

	[ -d ${S}/board/ti/j722s_bak ] && rm -rf ${S}/board/ti/j722s_bak
	mv ${S}/board/ti/j722s ${S}/board/ti/j722s_bak
	cp -r ${WORKDIR}/j722s-ecu1270/board/ti/j722s_adv ${S}/board/ti/j722s
}

	
#cp ${WORKDIR}/j722s-ecu1270/arch/arm/dts/*.dtsi ${S}/arch/arm/dts/
#cp ${WORKDIR}/j722s-ecu1270/arch/arm/dts/k3-j722s-r5-ecu1270.dts ${S}/arch/arm/dts/k3-j722s-r5-evm.dts
#cp -f ${WORKDIR}/j722s-ecu1270/configs/j722s_ecu1270_r5_defconfig ${S}/configs/j722s_evm_r5_defconfig