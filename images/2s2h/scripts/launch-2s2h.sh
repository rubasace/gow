#!/usr/bin/env bash
# Launch wrapper, run by `launcher` inside the compositor (as 'retro'). Per-user prep already
# ran in /opt/gow/startup.d/10-2s2h-config.sh, which exports S2H_ROM_PATH (the ROM to extract
# from) when there's no mm.o2r yet.
#
#   mm.o2r present  -> exec the binary, ZERO prompts.
#   mm.o2r missing  -> build it HEADLESSLY with the bundled ZAPD CLI (see 2s2h-lib.sh), publish
#                      it to /roms, then exec -> the binary finds it via the cont-init bundle
#                      bridge, ZERO prompts. Why not let 2S2H extract itself: its in-app
#                      extractor (InitOTR) is gated behind a blocking SDL "Generate one now?"
#                      box and a zenity/kdialog file picker base-app doesn't ship — a Moonlight
#                      gamepad can dismiss neither, and the argv extract path SoH uses is dead
#                      code in 2S2H 4.0.2.
#   ZAPD failed     -> fall back to 2S2H's own extractor: drop the ROM into its search dir (the
#                      home) and exec plainly. That still needs a MOUSE to click through once,
#                      but it's a real escape hatch instead of a hang.
#
# No `set -e`: extraction failure must fall through to the fallback, not abort the launch.
set -uo pipefail

BIN=/opt/2s2h/usr/bin/2s2h.elf
HOME_DIR="${SHIP_HOME:-$HOME}"
SHARED_DIR="${S2H_SHARED:-/roms}"
MARKER="$SHARED_DIR/.2s2h-o2r-version"
EXTRACT_LOG="$HOME_DIR/2s2h-extract.log"
cd "$HOME_DIR" 2>/dev/null || true

# shellcheck source=/dev/null
source /opt/2s2h/2s2h-lib.sh   # fsize, publish_*, promote_o2r, detect_zapd_ver, zapd_extract

log() { echo "[2S2H] $*"; }
o2r_available() { [ -e mm.o2r ] || [ -e "$SHARED_DIR/mm.o2r" ]; }

if ! o2r_available && [ -n "${S2H_ROM_PATH:-}" ]; then
  ver="$(detect_zapd_ver "$S2H_ROM_PATH")"
  # Prefer publishing the shared (common) copy; fall back to the per-user home if /roms is RO.
  if [ -d "$SHARED_DIR" ] && [ -w "$SHARED_DIR" ]; then dest="$SHARED_DIR/mm.o2r"; else dest="$HOME_DIR/mm.o2r"; fi
  log "First run: building mm.o2r from the ROM headlessly via ZAPD ($ver) -> $dest"
  log "      (takes a moment; full extractor output in $EXTRACT_LOG)"
  if zapd_extract "$S2H_ROM_PATH" "$ver" "$dest" "$EXTRACT_LOG"; then
    log "mm.o2r generated."
    if [ "$dest" = "$SHARED_DIR/mm.o2r" ]; then publish_string "${S2H_VERSION:-unknown}" "$MARKER" || true; fi
  else
    log "Headless ZAPD extraction failed (see $EXTRACT_LOG) -> falling back to 2S2H's own extractor."
    log "      It will pop a 'Generate one now?' dialog; dismiss it with a MOUSE (one-time)."
    # 2S2H's extractor searches GetAppDirectoryPath() (= the home) for the ROM; symlinking it
    # there lets it auto-detect and avoids the (missing) zenity/kdialog file picker.
    ln -sf "$S2H_ROM_PATH" "./$(basename "$S2H_ROM_PATH")" 2>/dev/null || true
  fi
fi

if o2r_available; then
  log "Launching with mm.o2r present (no prompts)."
else
  log "Launching 2 Ship 2 Harkinian."
fi
exec "$BIN"
