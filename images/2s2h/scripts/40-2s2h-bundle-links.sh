#!/usr/bin/env bash
# Sourced as ROOT from /etc/cont-init.d/ by base-app's entrypoint, before it drops to 'retro'
# and before the compositor. Bridges the shared mm.o2r INTO the image bundle so 2S2H finds it
# via LocateFileAcrossAppDirs (bundle step) with NO symlink in the per-user home.
#
# Why root + why the bundle: /opt/2s2h is root-owned (baked by the image), so only root can
# create links there — and the 'retro' startup.d fragment can't. The shared mount is already
# in place at cont-init time. A dangling link (when /roms/mm.o2r doesn't exist yet) is harmless:
# std::filesystem::exists() follows it, returns false, and 2S2H falls through to regeneration.
# (Majora's Mask has no Master Quest, so there's only mm.o2r to bridge.)
SHARED_DIR="${S2H_SHARED:-/roms}"
BUNDLE=/opt/2s2h/usr/bin
for o2r in mm.o2r; do
  ln -sfn "$SHARED_DIR/$o2r" "$BUNDLE/$o2r"
done
