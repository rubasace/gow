#!/usr/bin/env bash
# Launch wrapper, run by `launcher` inside the compositor (as 'retro'). Per-user prep already
# ran in /opt/gow/startup.d/10-2s2h-config.sh, which exports S2H_ROM_PATH (the ROM to extract
# from) when there's no mm.o2r yet.
#
#   mm.o2r present  -> exec the binary, ZERO prompts.
#   mm.o2r missing  -> build it HEADLESSLY with the bundled ZAPD CLI (see 2s2h-lib.sh), streaming
#                      ZAPD's output to the container logs, then exec -> the binary finds it via
#                      the cont-init bundle bridge, ZERO prompts. Why not let 2S2H extract itself:
#                      its in-app extractor (InitOTR) is gated behind a blocking SDL "Generate one
#                      now?" box and a zenity/kdialog file picker base-app doesn't ship — a
#                      Moonlight gamepad can dismiss neither, and the argv extract path SoH uses is
#                      dead code in 2S2H 4.0.2.
#   extraction fails-> log the error, tear down the compositor and exit. We do NOT launch the
#                      binary into its GUI extractor (a gamepad can't drive it); failing loudly and
#                      ending the session beats a silent hang on an un-dismissable dialog.
#
# No `set -e`: we branch on the extraction result explicitly and exit on failure.
set -uo pipefail

BIN=/opt/2s2h/usr/bin/2s2h.elf
HOME_DIR="${SHIP_HOME:-$HOME}"
SHARED_DIR="${S2H_SHARED:-/roms}"
MARKER="$SHARED_DIR/.2s2h-o2r-version"
cd "$HOME_DIR" 2>/dev/null || true

# shellcheck source=/dev/null
source /opt/2s2h/2s2h-lib.sh   # publish_*, promote_o2r, detect_zapd_ver, zapd_extract

# base-app runs us as the sway session command (`exec <us> && killall sway`), so it only tears the
# compositor down when we exit 0 — a failure would otherwise leave the container up on an empty
# desktop ("stuck"). So we stop the compositor ourselves on every exit path: any failure that keeps
# the game from running, and the normal game exit too, must end the session.
stop_compositor() { killall sway gamescope 2>/dev/null || true; }

log() { echo "[2S2H] $*"; }
die() { echo "[2S2H] ERROR: $*" >&2; stop_compositor; exit 1; }
o2r_available() { [ -e mm.o2r ] || [ -e "$SHARED_DIR/mm.o2r" ]; }

if ! o2r_available; then
  [ -n "${S2H_ROM_PATH:-}" ] || die "no mm.o2r and no ROM in $SHARED_DIR. Provide a supported NTSC-U .z64 or a prebuilt mm.o2r."

  ver="$(detect_zapd_ver "$S2H_ROM_PATH")"
  # Prefer publishing the shared (common) copy; fall back to the per-user home if /roms is RO.
  if [ -d "$SHARED_DIR" ] && [ -w "$SHARED_DIR" ]; then dest="$SHARED_DIR/mm.o2r"; else dest="$HOME_DIR/mm.o2r"; fi
  log "First run: building mm.o2r from the ROM headlessly via ZAPD ($ver) -> $dest (output follows)"

  if ! zapd_extract "$S2H_ROM_PATH" "$ver" "$dest"; then
    die "ZAPD failed to generate mm.o2r from '$S2H_ROM_PATH' (output above). Verify it's a supported NTSC-U dump (sha1 d6133ace… for N64 1.0, 9743aa02… for GC) at https://2ship.equipment/."
  fi
  log "mm.o2r generated."
  if [ "$dest" = "$SHARED_DIR/mm.o2r" ]; then publish_string "${S2H_VERSION:-unknown}" "$MARKER" || true; fi
fi

log "Launching with mm.o2r present (no prompts)."
"$BIN"
rc=$?
stop_compositor   # end the streaming session when the game exits, whatever the exit code
exit "$rc"
