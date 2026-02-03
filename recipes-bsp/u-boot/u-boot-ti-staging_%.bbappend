FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += " \
	file://keys \
"

#SRC_URI:append:j722s-ecu1270 = " file://0001-u-boot-ti-staging-init-commit-for-ecu1270-es2-1.patch "
SRC_URI:append:j722s-ecu1270 = " file://0001-source-code-mod-for-ECU1270.patch "
src_uri:append:j722s-ecu1270 = " file://0002-modify-dts-for-ecu1270.patch "
src_uri:append:j722s-ecu1270 = " file://0003-add-ddr-config-for-4g-version.patch "
src_uri:append:j722s-ecu1270 = " file://0004-addd-dtsi-for-2G-DDR-used-by-sunday-powers.patch "
src_uri:append:j722s-ecu1270 = " file://0005-enable-phy-on-u-boot-for-SI-testing.patch "
SRC_URI:append:j722s-ecu1270 = " file://rauc_env.cfg "

do_configure:prepend() {
	if [[ -f "${WORKDIR}/keys/custMpk.pem" ]] && [[ -f "${WORKDIR}/keys/custMpk.crt" ]] && [[ -f "${WORKDIR}/keys/custMpk.key" ]]; then
		echo "Overwriting U-Boot built-in key"
		cp -f ${WORKDIR}/keys/custMpk.pem ${S}/arch/arm/mach-k3/keys/custMpk.pem
		cp -f ${WORKDIR}/keys/custMpk.crt ${S}/arch/arm/mach-k3/keys/custMpk.crt
		cp -f ${WORKDIR}/keys/custMpk.key ${S}/arch/arm/mach-k3/keys/custMpk.key
	fi
}


