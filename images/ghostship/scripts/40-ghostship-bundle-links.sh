#!/usr/bin/env bash
# Sourced as ROOT from /etc/cont-init.d/ by base-app's entrypoint, before it drops to 'retro'
# and before the compositor. Bridges the shared sm64.o2r INTO the image bundle so Ghostship
# finds it via LocateFileAcrossAppDirs (bundle step) with NO symlink in the per-user home.
#
# Why root + why the bundle: /opt/ghostship is root-owned (baked by the image), so only root can
# create links there — and the 'retro' startup.d fragment can't. The shared mount is already in
# place at cont-init time. A dangling link (when /roms/sm64.o2r doesn't exist yet) is harmless:
# std::filesystem::exists() follows it, returns false, and Ghostship falls through to generation.
# (Super Mario 64 has a single ROM archive, so there's only sm64.o2r to bridge.)
SHARED_DIR="${GHOSTSHIP_SHARED:-/roms}"
BUNDLE=/opt/ghostship/usr/bin
for o2r in sm64.o2r; do
  ln -sfn "$SHARED_DIR/$o2r" "$BUNDLE/$o2r"
done
