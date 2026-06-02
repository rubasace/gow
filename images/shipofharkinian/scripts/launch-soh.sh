#!/usr/bin/env bash
# Thin launch wrapper, run by `launcher` inside the compositor (as 'retro'). All per-user
# prep already ran in /opt/gow/startup.d/10-soh-config.sh; here we only exec the binary,
# passing the ROM as an argument when that fragment set SOH_ROM_ARG. Kept as a wrapper so
# the ROM path stays a single quoted arg (launcher/sway would split it on spaces).
set -euo pipefail

BIN=/opt/soh/usr/bin/soh.elf
cd "${SHIP_HOME:-$HOME}" 2>/dev/null || true

if [ -n "${SOH_ROM_ARG:-}" ]; then
  echo "[SoH] Launching with ROM: $SOH_ROM_ARG"
  exec "$BIN" "$SOH_ROM_ARG"
else
  echo "[SoH] Launching (oot.o2r present / no ROM arg)."
  exec "$BIN"
fi
