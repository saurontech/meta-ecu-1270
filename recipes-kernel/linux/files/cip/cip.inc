# cip.inc for kernel recipes that do NOT inherit kernel-yocto (do_patch is the python task from patch.bbclass).
# Tested on ECU-1270 (meta-ti scarthgap) with "bitbake linux-ti-staging -c patch", 2026-11-13.
# Place it in the CIP directory next to cip-series.inc and add to the kernel bbappend
# (path relative to the bbappend, for example "require files/cip/cip.inc"):
#     require <dir>/cip/cip.inc
# <dir> (the directory that holds cip/) must be in FILESEXTRAPATHS of the bbappend,
# otherwise bitbake cannot find the file://cip/<tag>/ entries.
# The MACHINE override ":j722s-ecu1270" below is the same as in cip-series.inc;
# remove it to apply to every MACHINE.
# The CIP folders are unpacked to UNPACKDIR (Yocto 5.1 styhead and later) or WORKDIR (older
# releases). The folder path below uses whichever one this Yocto release defines, so the same
# file works before and after a Yocto upgrade.
# A shell prepend cannot be added to a python task, so the CIP folders are applied in their own task
# between do_unpack and do_patch; do_patch then applies the product patches from SRC_URI on top.
# ${S} must be a git checkout (git:// in SRC_URI), because the patches are applied with git am.

require cip-series.inc

# Directory entries do not end in .patch, so patch.bbclass does not try to apply them itself.
SRC_URI:append:j722s-ecu1270 = " ${@' '.join('file://cip/%s/' % b for b in d.getVar('CIP_BATCHES').split())}"

do_cip_patch() {
    cd ${S}
    # Disable automatic gc in the kernel source repo: tens of thousands of CIP
    # commits leave many loose objects, and a later plain git command would
    # start a background gc that can hold HEAD.lock while the build changes HEAD.
    git config gc.auto 0
    git config maintenance.auto false
    for batch in ${CIP_BATCHES}; do
        dir=${@d.getVar('UNPACKDIR') or d.getVar('WORKDIR')}/cip/$batch
        # --no-3way: accept only patches that apply as-is
        # gc.auto=0: tens of thousands of commits trigger auto gc, which can lock HEAD and make git am fail
        # sort -V:   numeric order, so 10000-*.patch comes after 9999-*.patch, and local-*.patch comes last
        # user.name, user.email, --committer-date-is-author-date: the same commit IDs on every build
        #            and every machine (the -g<commit> part of uname -r comes from the last CIP commit)
        if ! ls $dir | grep '\.patch$' | sort -V | sed "s|^|$dir/|" \
            | xargs -d '\n' sh -c 'git -c gc.auto=0 -c user.name="${PATCH_GIT_USER_NAME}" -c user.email="${PATCH_GIT_USER_EMAIL}" am --no-3way --committer-date-is-author-date -q "$@" || exit 255' sh; then
            failed=$(git am --show-current-patch=raw 2>/dev/null | grep -m1 '^Subject:' || true)
            git am --abort || true
            bbfatal "CIP $batch: git am failed at: $failed"
        fi
    done
}
# kernel.bbclass moves ${S} to STAGING_KERNEL_DIR in do_symlink_kernsrc, which also runs
# after do_unpack. Run after it, so git am never works in a directory that is being moved.
addtask cip_patch after do_unpack do_symlink_kernsrc before do_patch
do_cip_patch[depends] += "git-native:do_populate_sysroot"
