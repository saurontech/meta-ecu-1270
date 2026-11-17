FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

# CIP SLTS patches (linux-6.12.y-cip), applied before the product patches below
require files/cip/cip.inc

SRC_URI:append:j722s-ecu1270 = " file://0001-add-dts-for-ecu-1270-ES2-hardware.patch"
SRC_URI:append:j722s-ecu1270 = " file://0002-add-hdmi-support.patch"
SRC_URI:append:j722s-ecu1270 = " file://0003-CPU-used-on-ecu1270-has-no-VPU-and-RTI15.patch"
SRC_URI:append:j722s-ecu1270 = " file://0004-enable-gpio-wdt.patch"
SRC_URI:append:j722s-ecu1270 = " file://rauc.cfg"
SRC_URI:append:j722s-ecu1270 = " file://gpio_wdt.cfg"
SRC_URI:append:j722s-ecu1270 = " file://uart.cfg"
SRC_URI:append:j722s-ecu1270 = " file://tpm.cfg"
SRC_URI:append:j722s-ecu1270 = " file://luks.cfg"
SRC_URI:append:j722s-ecu1270 = " file://overlayfs.cfg"

KERNEL_CONFIG_FRAGMENTS += " ${WORKDIR}/rauc.cfg"
KERNEL_CONFIG_FRAGMENTS += " ${WORKDIR}/uart.cfg"
KERNEL_CONFIG_FRAGMENTS += " ${WORKDIR}/gpio_wdt.cfg"
KERNEL_CONFIG_FRAGMENTS += " ${WORKDIR}/tpm.cfg"
KERNEL_CONFIG_FRAGMENTS += " ${WORKDIR}/luks.cfg"
KERNEL_CONFIG_FRAGMENTS += " ${WORKDIR}/overlayfs.cfg"
