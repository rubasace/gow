#!/usr/bin/env bash
# Launch wrapper, run by `launcher` inside the compositor (as 'retro'). Per-user prep already ran
# in /opt/gow/startup.d/10-ghostship-config.sh, which exports GHOSTSHIP_ROM_PATH (the ROM to
# extract from) when there's no sm64.o2r yet.
#
#   sm64.o2r present  -> launch the binary, ZERO prompts.
#   sm64.o2r missing  -> build it HEADLESSLY with the bundled Torch CLI (see ghostship-lib.sh),
#                        streaming Torch's output to the container logs, then launch -> the binary
#                        finds it in the home (10-config symlinks the shared copy in), ZERO prompts.
#                        Why not let Ghostship extract itself: on Linux its in-app extractor draws a
#                        blocking ImGui "Generate one now?" popup and then a zenity/kdialog file picker
#                        base-app doesn't ship — a Moonlight gamepad can drive neither.
#   extraction fails  -> log the error, tear down the compositor and exit. We do NOT launch the
#                        binary into its GUI extractor (a gamepad can't drive it); failing loudly
#                        and ending the session beats a silent hang on an un-dismissable dialog.
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

# base-app runs us as the sway session command (`exec <us> && killall sway`), so it only tears the
# compositor down when we exit 0 — a failure would otherwise leave the container up on an empty
# desktop ("stuck"). So we stop the compositor ourselves on every exit path: any failure that keeps
# the game from running, and the normal game exit too, must end the session.
stop_compositor() { killall sway gamescope 2>/dev/null || true; }

log() { echo "[Ghostship] $*"; }
die() { echo "[Ghostship] ERROR: $*" >&2; stop_compositor; exit 1; }
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

# Ghostship reads sm64.o2r from the data dir ONLY (GetPathRelativeToAppDirectory), so make sure the
# shared copy is symlinked into the home before launch — covers a fresh extraction and a pre-existing
# shared copy alike. Without this the game can't find it and bails to its (headless-undriveable)
# extractor with exit(1).
ensure_o2r_in_home

log "Launching with sm64.o2r present (no prompts)."
# Mirror the game's stdout+stderr both to the container log AND to a host-readable file in the
# shared dir — the per-user home isn't mounted on the host, and the game otherwise writes its real
# log to a file we can't see. This makes a startup failure diagnosable from outside the container.
run_log="$SHARED_DIR/ghostship-last-run.log"
env LD_LIBRARY_PATH="$LIBS:${LD_LIBRARY_PATH:-}" "$BIN" 2>&1 | tee "$run_log" 2>/dev/null
rc=${PIPESTATUS[0]}
log "Ghostship exited with code $rc (stdout/stderr mirrored to $run_log)."
# Also surface libultraship's own file log (it logs there, not to stdout). Search broadly — the
# path/name varies by version — dump the newest to the container log and copy it beside run_log.
newest_log="$(find "$HOME_DIR" -maxdepth 3 -type f -name '*.log' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)"
if [ -n "${newest_log:-}" ]; then
  echo "[Ghostship] ===== game log: $newest_log =====" >&2
  tail -n 80 "$newest_log" >&2 || true
  echo "[Ghostship] ===== end game log =====" >&2
  cp -f "$newest_log" "$SHARED_DIR/ghostship-game.log" 2>/dev/null || true
else
  echo "[Ghostship] no libultraship .log found under $HOME_DIR (crashed before logging?)" >&2
fi
stop_compositor   # end the streaming session when the game exits, whatever the exit code
exit "$rc"
