FILESEXTRAPATHS:prepend := "${THISDIR}/files:"


SRC_URI:append:j722s-ecu1270 = " file://0001-add-dts-for-ecu-1270-ES2-hardware.patch"
SRC_URI:append:j722s-ecu1270 = " file://rauc.cfg"


KERNEL_CONFIG_FRAGMENTS += " ${WORKDIR}/rauc.cfg"
