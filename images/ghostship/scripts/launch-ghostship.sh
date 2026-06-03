#!/usr/bin/env bash
# Launch wrapper, run by `launcher` inside the compositor (as 'retro'). Per-user prep already ran
# in /opt/gow/startup.d/10-ghostship-config.sh, which exports GHOSTSHIP_ROM_PATH (the ROM to
# extract from) when there's no sm64.o2r yet.
#
#   sm64.o2r present  -> exec the binary, ZERO prompts.
#   sm64.o2r missing  -> build it HEADLESSLY with the bundled Torch CLI (see ghostship-lib.sh),
#                        streaming Torch's output to the container logs, then exec -> the binary
#                        finds it via the cont-init bundle bridge, ZERO prompts. Why not let
#                        Ghostship extract itself: on Linux its in-app extractor draws a blocking
#                        ImGui "Generate one now?" popup and then a zenity/kdialog file picker
#                        base-app doesn't ship — a Moonlight gamepad can drive neither.
#   extraction fails  -> log the error and EXIT non-zero. We do NOT launch the binary into its GUI
#                        extractor (a gamepad can't drive it); failing loudly in the logs beats a
#                        silent hang on an un-dismissable dialog.
#
# No `set -e`: we branch on the extraction result explicitly and exit on failure.
set -uo pipefail

BIN=/opt/ghostship/usr/bin/Ghostship
LIBS=/opt/ghostship/usr/lib                 # bundled SDL2/ssl/fmt/spdlog/tcc/zip/zstd
HOME_DIR="${SHIP_HOME:-$HOME}"
SHARED_DIR="${GHOSTSHIP_SHARED:-/roms}"
MARKER="$SHARED_DIR/.ghostship-o2r-version"
cd "$HOME_DIR" 2>/dev/null || true

# shellcheck source=/dev/null
source /opt/ghostship/ghostship-lib.sh   # publish_*, promote_o2r, rom_supported, torch_extract

log() { echo "[Ghostship] $*"; }
die() { echo "[Ghostship] ERROR: $*" >&2; exit 1; }
o2r_available() { [ -e sm64.o2r ] || [ -e "$SHARED_DIR/sm64.o2r" ]; }

if ! o2r_available; then
  [ -n "${GHOSTSHIP_ROM_PATH:-}" ] || die "no sm64.o2r and no ROM in $SHARED_DIR. Provide a supported Super Mario 64 .z64 (US or JP) or a prebuilt sm64.o2r."

  rom_supported "$GHOSTSHIP_ROM_PATH" || die "'$GHOSTSHIP_ROM_PATH' is not a supported Super Mario 64 dump. Need US (sha1 9bef1128…) or JP (sha1 8a20a5c8…) in .z64 format — verify at https://www.romhacking.net/hash/."

  # Prefer publishing the shared (common) copy; fall back to the per-user home if /roms is RO.
  if [ -d "$SHARED_DIR" ] && [ -w "$SHARED_DIR" ]; then dest="$SHARED_DIR/sm64.o2r"; else dest="$HOME_DIR/sm64.o2r"; fi
  log "First run: building sm64.o2r from the ROM headlessly via Torch -> $dest (output follows)"

  if ! torch_extract "$GHOSTSHIP_ROM_PATH" "$dest"; then
    die "Torch failed to generate sm64.o2r from '$GHOSTSHIP_ROM_PATH' (output above)."
  fi
  log "sm64.o2r generated."
  if [ "$dest" = "$SHARED_DIR/sm64.o2r" ]; then publish_string "${GHOSTSHIP_VERSION:-unknown}" "$MARKER" || true; fi
fi

log "Launching with sm64.o2r present (no prompts)."
exec env LD_LIBRARY_PATH="$LIBS:${LD_LIBRARY_PATH:-}" "$BIN"
