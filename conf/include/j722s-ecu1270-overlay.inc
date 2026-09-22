# j722s-ecu1270-overlay.inc — Single source of truth for ECU1270 overlay root.
# Everything is gated behind one boolean so the layer behaves exactly like
# "no overlay" when disabled (safe to keep resident), matching the RAUC and
# LUKS includes.

OVERLAY_ROOT_ENABLED ?= "0"

# NOTE: INITRAMFS_IMAGE_BUNDLE may ONLY be set from a conf file (oe-core
# restriction), which is exactly why this lives here and not in an image
# recipe.
INITRAMFS_IMAGE        = "${@'initramfs-overlay-image' if d.getVar('OVERLAY_ROOT_ENABLED') == '1' else ''}"
INITRAMFS_IMAGE_BUNDLE = "${@'1' if d.getVar('OVERLAY_ROOT_ENABLED') == '1' else '0'}"

# --- /boot/fitImage fixup (mandatory) -----------------------------------
# INITRAMFS_IMAGE_BUNDLE=1 makes oe-core skip installing the fitImage into the
# rootfs (kernel.bbclass: the bundled FIT does not exist yet at do_install
# time).
#
# The initramfs image itself MUST be excluded: it is an image too, so a blanket
# do_rootfs dependency on virtual/kernel:do_deploy would loop (the kernel needs
# the initramfs image to bundle). One flag, two uses.
OVERLAY_FITIMAGE_FIXUP = "${@'1' if d.getVar('OVERLAY_ROOT_ENABLED') == '1' \
    and d.getVar('PN') != d.getVar('INITRAMFS_IMAGE') else '0'}"

ROOTFS_POSTPROCESS_COMMAND:append = "${@' ecu1270_install_boot_fitimage;' if d.getVar('OVERLAY_FITIMAGE_FIXUP') == '1' else ''}"
do_rootfs[depends] += "${@'virtual/kernel:do_deploy' if d.getVar('OVERLAY_FITIMAGE_FIXUP') == '1' else ''}"

ecu1270_install_boot_fitimage() {
    # Already resolvable? Then oe-core (or something else) provided it and we
    # must not second-guess. [ -e ] is false for a dangling symlink, which is
    # exactly the case we need to repair.
    if [ -e "${IMAGE_ROOTFS}/boot/fitImage" ]; then
        return
    fi
    # rm first: install(1) would follow the dangling symlink and create the
    # versioned target filename instead of /boot/fitImage.
    rm -f "${IMAGE_ROOTFS}/boot/fitImage"
    install -m 0644 "${DEPLOY_DIR_IMAGE}/fitImage-${MACHINE}.bin" \
                    "${IMAGE_ROOTFS}/boot/fitImage"
}

python () {
    if d.getVar('OVERLAY_ROOT_ENABLED') != '1':
        return

    # The --rauc flash layout uses every MBR primary partition, so there is
    # none spare for a persistent overlay upper. Not fatal - tmpfs upper is
    # the recommended setup anyway. Deliberately no partition numbers here:
    # the flash tool owns the layout and prints it.
    if d.getVar('RAUC_ENABLED') == '1':
        bb.note("ECU1270 overlay: the --rauc flash layout already uses every MBR "
                "primary partition, so a persistent overlay upper has to be tmpfs "
                "(recommended) or a subdirectory of the existing data partition. "
                "See the overlay doc, section 10.")

    # The initramfs has no cryptsetup / TPM stack, so it cannot unlock ANY LUKS
    # container - which partition LUKS owns is irrelevant to that fact.
    if d.getVar('LUKS_DATA_ENABLED') == '1':
        bb.note("ECU1270 overlay: the initramfs cannot unlock a LUKS container "
                "(no cryptsetup/TPM in there), so do not point overlayrwdev= at "
                "LUKS_DATA_DEVICE (%s). Keep the overlay upper on tmpfs."
                % (d.getVar('LUKS_DATA_DEVICE') or 'unset'))
}
