SUMMARY = "Minimal initramfs image with overlay-root support (ECU-1270)"
LICENSE = "MIT"

# busybox provides sh, mount, switch_root, awk, grep, modprobe, sleep, mknod...
# devtmpfs handles device nodes — no mdev needed.
PACKAGE_INSTALL = " \
    initramfs-overlay \
    busybox \
    base-passwd \
"

PACKAGE_EXCLUDE = "kernel-image-*"

IMAGE_FEATURES = ""
IMAGE_LINGUAS  = ""
IMAGE_FSTYPES  = "${INITRAMFS_FSTYPES}"

# MANDATORY. image-artifact-names.bbclass sets IMAGE_NAME_SUFFIX ??= ".rootfs",
# but kernel.bbclass's copy_initramfs() looks for
#   ${DEPLOY_DIR_IMAGE}/${INITRAMFS_IMAGE_NAME}.cpio.gz
# where INITRAMFS_IMAGE_NAME = "${INITRAMFS_IMAGE}${IMAGE_MACHINE_SUFFIX}"
# with NO suffix.
IMAGE_NAME_SUFFIX = ""

inherit core-image

IMAGE_ROOTFS_SIZE        = "8192"
IMAGE_ROOTFS_EXTRA_SPACE = "0"
