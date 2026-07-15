# ---------------------------------------------------------------------------
# Fix: pseudo <-> GNU tar openat2() incompatibility during do_package.
#
# oe-core (Arago / scarthgap) pins pseudo at SRCREV 28dcefb (PV 1.9.0+git),
# which predates pseudo's openat2 wrapper (first shipped in tag pseudo-1.9.4,
# 2026-04-20). Modern host GNU tar (>=1.35, carries the CVE-2025-45582 security
# backport) uses openat2(RESOLVE_BENEATH) to create nested dirs while
# extracting; the old pseudo cannot intercept openat2, loses the dir-fd
# mapping, and do_package's "tar | tar" (perform_packagecopy) fails with:
#     got *at() syscall for unknown directory
#     tar: ./...: Cannot mkdir: Bad address
#
# We bump pseudo to upstream pseudo-1.9.8 (823895ba, has the openat2 wrapper)
# for THIS build only, leaving oe-core untouched.
#
# See doc/0065_fix_bad_epoll_and_pseudo_wrapper/fix_pseudo_wrapper_plan.md
# ---------------------------------------------------------------------------

# The exact base SRCREV this workaround is meant to patch over. Guarding on
# this makes the whole bbappend SELF-DISABLING: the moment oe-core bumps pseudo
# to any other SRCREV (in practice only ever forward, to >=1.9.4 which already
# has the openat2 wrapper), everything below turns into a no-op, so we never
# pin pseudo *backward* nor fight a newer base recipe's patch set.
PSEUDO_KNOWN_BAD_SRCREV = "28dcefb809ce95db997811b5662f0b893b9923e0"

# Upstream pseudo-1.9.8 (has openat2 wrapper + later fixes).
PSEUDO_OPENAT2_SRCREV = "823895ba708c63f6ae4dcbfc266210f26c02c698"

python () {
    known_bad = d.getVar('PSEUDO_KNOWN_BAD_SRCREV')
    if d.getVar('SRCREV') != known_bad:
        # oe-core has moved pseudo forward -> assume it now has the openat2
        # wrapper (>=1.9.4). Do nothing and remind the maintainer to drop
        # this bbappend after confirming the base pseudo is fixed.
        bb.warn("meta-ecu-1270: base pseudo SRCREV is no longer %s; assuming "
                "oe-core bumped pseudo to a version that already has the openat2 "
                "wrapper. The openat2 workaround (pseudo_git.bbappend) is now a "
                "no-op and should be verified & removed." % known_bad)
        return

    # --- Base is still the broken pre-openat2 pseudo: apply the workaround. ---
    d.setVar('SRCREV', d.getVar('PSEUDO_OPENAT2_SRCREV'))

    # oe-core's two source-level patches do NOT apply cleanly at 1.9.8:
    #   * 0001-configure-Prune-PIE-flags.patch : re-applied idempotently in
    #     do_unpack:append below (append the pie-strip sed to configure).
    #   * older-glibc-symbols.patch (native/nativesdk): re-applied by substring
    #     replacement in do_unpack:append below.
    # NOTE: glibc238.patch is intentionally KEPT -- it is still needed at 1.9.8
    # and its context still matches, so do_patch applies it normally.
    drop = (
        'file://0001-configure-Prune-PIE-flags.patch',
        'file://older-glibc-symbols.patch',
    )
    src_uri = (d.getVar('SRC_URI') or '').split()
    d.setVar('SRC_URI', ' '.join(u for u in src_uri if u not in drop))

    # Marker consumed by do_unpack:append (which runs at task time, after this
    # anonymous python has already rewritten SRCREV, so it cannot re-check the
    # SRCREV guard itself).
    d.setVar('PSEUDO_OPENAT2_WORKAROUND', '1')
}

python do_unpack:append() {
    if d.getVar('PSEUDO_OPENAT2_WORKAROUND') != '1':
        return

    import os
    s = d.getVar('S')

    # (A) Re-apply 0001-configure-Prune-PIE-flags.patch effect, idempotently.
    #     OE injects -fpie/-pie globally for security; pseudo's Makefile reuses
    #     CFLAGS as LDFLAGS, so -pie leaks into the -shared libpseudo.so link
    #     and conflicts. Strip -fpie/-pie from the generated Makefile. Appending
    #     the sed at EOF of configure is equivalent (Makefile is generated
    #     earlier in configure) and survives upstream line shifts.
    configure = os.path.join(s, 'configure')
    pie_line = "sed -i -e 's/\\-[f]*pie//g' Makefile"
    if os.path.exists(configure):
        with open(configure) as f:
            cfg = f.read()
        if pie_line not in cfg:
            with open(configure, 'a') as f:
                f.write("\n# meta-ecu-1270: re-apply pruned PIE flags "
                        "(was 0001-configure-Prune-PIE-flags.patch)\n")
                f.write(pie_line + "\n")

    # (B) Re-apply older-glibc-symbols.patch (native / nativesdk only).
    if not (bb.data.inherits_class('native', d) or bb.data.inherits_class('nativesdk', d)):
        return

    # (B1) Makefile.in: put the prebuilt (older-glibc) lib dir ahead of the
    #      recipe libs on the libpseudo.so link line.
    makefile_in = os.path.join(s, 'Makefile.in')
    with open(makefile_in) as f:
        content = f.read()
    old = '$(CC) $(CFLAGS) $(CFLAGS_PSEUDO) -shared -o $(LIBPSEUDO) \\'
    new = '$(CC) $(CFLAGS)  -Lprebuilt/$(shell uname -m)-linux/lib/ $(CFLAGS_PSEUDO) -shared -o $(LIBPSEUDO) \\'
    if old not in content:
        bb.fatal('pseudo openat2 workaround: Makefile.in link-rule anchor not '
                 'found in %s (upstream layout changed; re-check this bbappend)' % makefile_in)
    content = content.replace(old, new, 1)
    with open(makefile_in, 'w') as f:
        f.write(content)

    # (B2) pseudo_wrappers.c: use glibc-internal __register_atfork instead of
    #      pthread_atfork so the native binary links against older glibc symbols.
    wrappers_c = os.path.join(s, 'pseudo_wrappers.c')
    with open(wrappers_c) as f:
        content = f.read()

    old = 'pthread_atfork(NULL, NULL, libpseudo_atfork_child);'
    new = '__register_atfork (NULL, NULL, libpseudo_atfork_child, &__dso_handle == NULL ? NULL : __dso_handle);'
    if old not in content:
        bb.fatal('pseudo openat2 workaround: atfork anchor not found in %s '
                 '(upstream layout changed; re-check this bbappend)' % wrappers_c)
    content = content.replace(old, new, 1)

    # The externs must be declared BEFORE "static void", otherwise the "static"
    # storage class collides with the "extern" declaration.
    old = 'static void\n_libpseudo_init(void) {'
    new = ('extern void *__dso_handle;\n'
           'extern int __register_atfork (void (*) (void), void (*) (void), void (*) (void), void *);\n\n'
           'static void\n_libpseudo_init(void) {')
    if old not in content:
        bb.fatal('pseudo openat2 workaround: _libpseudo_init anchor not found '
                 'in %s (upstream layout changed; re-check this bbappend)' % wrappers_c)
    content = content.replace(old, new, 1)

    with open(wrappers_c, 'w') as f:
        f.write(content)
}
