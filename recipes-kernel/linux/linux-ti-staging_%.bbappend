FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append:j722s-ecu1270 = " file://0001-add-dts-for-ecu-1270-ES2-hardware.patch"
SRC_URI:append:j722s-ecu1270 = " file://0002-add-hdmi-support.patch"
SRC_URI:append:j722s-ecu1270 = " file://0003-CPU-used-on-ecu1270-has-no-VPU-and-RTI15.patch"
SRC_URI:append:j722s-ecu1270 = " file://rauc.cfg"
SRC_URI:append:j722s-ecu1270 = " file://uart.cfg"

KERNEL_CONFIG_FRAGMENTS += " ${WORKDIR}/rauc.cfg"
KERNEL_CONFIG_FRAGMENTS += " ${WORKDIR}/uart.cfg"

# The following patches are eventpoll-related patches from the Linux kernel mailing list that 
# fix a use-after-free bug in the ep_remove() function. They are applied in order to ensure that
# the eventpoll implementation is safe and does not lead to memory corruption or crashes.
SRC_URI:append:j722s-ecu1270 = " \
            file://badepoll/0001-eventpoll-use-hlist_is_singular_node-in-__ep_remove.patch \
            file://badepoll/0002-eventpoll-split-__ep_remove.patch \
            file://badepoll/0003-eventpoll-kill-__ep_remove.patch \
            file://badepoll/0004-eventpoll-drop-vestigial-__-prefix-from-ep_remove_-f.patch \
            file://badepoll/0005-eventpoll-rename-ep_remove_safe-back-to-ep_remove.patch \
            file://badepoll/0006-eventpoll-move-epi_fget-up.patch \
            file://badepoll/0007-eventpoll-fix-ep_remove-struct-eventpoll-struct-file.patch \
            "