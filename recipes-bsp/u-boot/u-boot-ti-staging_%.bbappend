FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += " \
	file://keys \
"

SRC_URI:append:j722s-ecu1270 = " file://0001-try-to-fix-u-boot-ti-staging-issue-with-devtool.patch \
				 file://0002-rauc_default_env_and_mmcdev.patch \
				 file://rauc_env.cfg \
"

do_configure:prepend() {
	if [[ -f "${WORKDIR}/keys/custMpk.pem" ]] && [[ -f "${WORKDIR}/keys/custMpk.crt" ]] && [[ -f "${WORKDIR}/keys/custMpk.key" ]]; then
		echo "Overwriting U-Boot built-in key"
		cp -f ${WORKDIR}/keys/custMpk.pem ${S}/arch/arm/mach-k3/keys/custMpk.pem
		cp -f ${WORKDIR}/keys/custMpk.crt ${S}/arch/arm/mach-k3/keys/custMpk.crt
		cp -f ${WORKDIR}/keys/custMpk.key ${S}/arch/arm/mach-k3/keys/custMpk.key
	fi
}


