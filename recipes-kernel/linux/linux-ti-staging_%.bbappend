FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append:j722s-ecu1270 = " file://0001-add-dts-for-ecu-1270-ES2-hardware.patch"
SRC_URI:append:j722s-ecu1270 = " file://0002-add-hdmi-support.patch"
<<<<<<< Updated upstream
SRC_URI:append:j722s-ecu1270 = " file://0003-CPU-used-on-ecu1270-has-no-VPU-and-RTI15.patch"
=======
SRC_URI:append:j722s-ecu1270 = " file://0003-Add-pps-func.patch"
>>>>>>> Stashed changes
SRC_URI:append:j722s-ecu1270 = " file://rauc.cfg"
SRC_URI:append:j722s-ecu1270 = " file://uart.cfg"

KERNEL_CONFIG_FRAGMENTS += " ${WORKDIR}/rauc.cfg"
KERNEL_CONFIG_FRAGMENTS += " ${WORKDIR}/uart.cfg"

