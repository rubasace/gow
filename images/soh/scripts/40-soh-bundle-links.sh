#!/usr/bin/env bash
# Sourced as ROOT from /etc/cont-init.d/ by base-app's entrypoint, before it drops to 'retro'
# and before the compositor. Bridges the shared oot.o2r / oot-mq.o2r INTO the image bundle so
# SoH finds them via LocateFileAcrossAppDirs (bundle step) with NO symlink in the per-user home.
#
# Why root + why the bundle: /opt/soh is root-owned (baked by the image), so only root can
# create links there — and the 'retro' startup.d fragment can't. The shared mount is already
# in place at cont-init time. A dangling link (when /roms/oot.o2r doesn't exist yet) is harmless:
# std::filesystem::exists() follows it, returns false, and SoH falls through to regeneration.
SHARED_DIR="${SOH_SHARED:-/roms}"
BUNDLE=/opt/soh/usr/bin
for o2r in oot.o2r oot-mq.o2r; do
  ln -sfn "$SHARED_DIR/$o2r" "$BUNDLE/$o2r"
done
