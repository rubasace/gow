#!/usr/bin/env bash
# Thin launch wrapper, run by `launcher` inside the compositor (as 'retro'). Per-user prep
# already ran in /opt/gow/startup.d/10-soh-config.sh.
#
# Normal path: just exec the binary — oot.o2r is already available (cont-init bundle bridge ->
# /roms), so SoH starts with ZERO prompts.
#
# First-run / regenerated extraction: when there's no oot.o2r yet, SoH extracts it from the ROM
# and then parks on a "Run SoH?" confirm popup that appears BEFORE the controller is initialized
# -> it needs a keyboard, which a Moonlight gamepad user doesn't have. To keep it hands-free we
# run the extraction in the background, wait for the archive to be fully written (its size stops
# growing), kill that instance (popup and all), and relaunch clean -> the o2r now exists, so SoH
# starts with no prompts. This also covers MAJOR-version regenerations (same extract path).
#
# No `set -e`: we manage the background job, polling and kills explicitly.
set -uo pipefail

BIN=/opt/soh/usr/bin/soh.elf
HOME_DIR="${SHIP_HOME:-$HOME}"
SHARED_DIR="${SOH_SHARED:-/roms}"
cd "$HOME_DIR" 2>/dev/null || true

# shellcheck source=/dev/null
source /opt/soh/soh-lib.sh   # fsize, publish_file, publish_string, promote_o2r

# base-app runs us as the sway session command (`exec <us> && killall sway`), so it only tears the
# compositor down when we exit 0 — a failure would otherwise leave the container up on an empty
# desktop ("stuck"). So we stop the compositor ourselves on every exit path: any failure that keeps
# the game from running, and the normal game exit too, must end the session.
stop_compositor() { killall sway gamescope 2>/dev/null || true; }

o2r_available() {
  [ -e oot.o2r ] || [ -e oot-mq.o2r ] || [ -e "$SHARED_DIR/oot.o2r" ] || [ -e "$SHARED_DIR/oot-mq.o2r" ]
}

# Run SoH to extract oot.o2r from the ROM, then kill it once the archive is fully written, so
# nobody has to click the post-extraction popup.
extract_headless() { # <rom-path>
  local rom="$1" pid sz prev=-1 stable=0 i
  echo "[SoH] First run: extracting oot.o2r from the ROM (no interaction needed)..."
  # Output to /dev/null: the extraction UI is graphical; this also stops any stray child from
  # holding the launcher's stdout open after we kill the instance.
  "$BIN" "$rom" >/dev/null 2>&1 &
  pid=$!
  for i in $(seq 1 240); do
    kill -0 "$pid" 2>/dev/null || break              # extractor exited by itself (done or error)
    sz=0
    if   [ -e oot.o2r ];    then sz=$(fsize oot.o2r)
    elif [ -e oot-mq.o2r ]; then sz=$(fsize oot-mq.o2r)
    fi
    if [ "$sz" -gt 0 ] && [ "$sz" = "$prev" ]; then
      stable=$((stable + 1))
      [ "$stable" -ge 2 ] && break                   # size unchanged ~2s -> the copy finished
    else
      stable=0
    fi
    prev="$sz"
    sleep 1
  done
  kill "$pid" 2>/dev/null
  for i in 1 2 3 4 5; do kill -0 "$pid" 2>/dev/null || break; sleep 1; done
  kill -9 "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  echo "[SoH] Extraction finished; relaunching cleanly."
}

if [ -n "${SOH_ROM_ARG:-}" ] && ! o2r_available; then
  extract_headless "$SOH_ROM_ARG"
  # Promote the freshly-extracted o2r to /roms (+ stamp the version marker), drop the home copy.
  # Without this the regenerated o2r would sit in the home and the marker would stay missing.
  promote_o2r
fi

if o2r_available; then
  echo "[SoH] Launching with oot.o2r present (no prompts)."
  "$BIN"
  rc=$?
  stop_compositor   # end the streaming session when the game exits, whatever the exit code
  exit "$rc"
fi

# No usable oot.o2r. Do NOT launch the binary into its GUI extractor/confirm popup (a Moonlight
# gamepad can't drive it) — fail loudly and end the session instead of hanging on an un-dismissable
# dialog.
if [ -n "${SOH_ROM_ARG:-}" ]; then
  echo "[SoH] ERROR: extraction did not produce oot.o2r from '$SOH_ROM_ARG'. Verify the ROM (OoT NTSC 1.0 US) and that $SHARED_DIR is writable. Exiting." >&2
else
  echo "[SoH] ERROR: no oot.o2r and no ROM in $SHARED_DIR. Provide an OoT NTSC 1.0 US .z64 or a prebuilt oot.o2r. Exiting." >&2
fi
stop_compositor
exit 1
