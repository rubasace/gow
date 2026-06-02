#!/usr/bin/env bash
# Thin launch wrapper, run by `launcher` inside the compositor (as 'retro'). Per-user prep
# already ran in /opt/gow/startup.d/10-2s2h-config.sh.
#
# Normal path: just exec the binary — mm.o2r is already available (cont-init bundle bridge ->
# /roms), so 2S2H starts with ZERO prompts.
#
# First-run / regenerated extraction: when there's no mm.o2r yet, 2S2H extracts it from the ROM
# and then parks on a "Run 2S2H?" confirm popup that appears BEFORE the controller is initialized
# -> it needs a keyboard, which a Moonlight gamepad user doesn't have. To keep it hands-free we
# run the extraction in the background, wait for the archive to be fully written (its size stops
# growing), kill that instance (popup and all), and relaunch clean -> the o2r now exists, so 2S2H
# starts with no prompts. This also covers MAJOR-version regenerations (same extract path).
#
# No `set -e`: we manage the background job, polling and kills explicitly.
set -uo pipefail

BIN=/opt/2s2h/usr/bin/2s2h.elf
HOME_DIR="${SHIP_HOME:-$HOME}"
SHARED_DIR="${S2H_SHARED:-/roms}"
cd "$HOME_DIR" 2>/dev/null || true

# shellcheck source=/dev/null
source /opt/2s2h/2s2h-lib.sh   # fsize, publish_file, publish_string, promote_o2r

o2r_available() {
  [ -e mm.o2r ] || [ -e "$SHARED_DIR/mm.o2r" ]
}

# Run 2S2H to extract mm.o2r from the ROM, then kill it once the archive is fully written, so
# nobody has to click the post-extraction popup.
extract_headless() { # <rom-path>
  local rom="$1" pid sz prev=-1 stable=0 i
  echo "[2S2H] First run: extracting mm.o2r from the ROM (no interaction needed)..."
  # Output to /dev/null: the extraction UI is graphical; this also stops any stray child from
  # holding the launcher's stdout open after we kill the instance.
  "$BIN" "$rom" >/dev/null 2>&1 &
  pid=$!
  for i in $(seq 1 240); do
    kill -0 "$pid" 2>/dev/null || break              # extractor exited by itself (done or error)
    sz=0
    if [ -e mm.o2r ]; then sz=$(fsize mm.o2r); fi
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
  echo "[2S2H] Extraction finished; relaunching cleanly."
}

if [ -n "${S2H_ROM_ARG:-}" ] && ! o2r_available; then
  extract_headless "$S2H_ROM_ARG"
  # Promote the freshly-extracted o2r to /roms (+ stamp the version marker), drop the home copy.
  # Without this the regenerated o2r would sit in the home and the marker would stay missing.
  promote_o2r
fi

if o2r_available; then
  echo "[2S2H] Launching with mm.o2r present (no prompts)."
  exec "$BIN"
elif [ -n "${S2H_ROM_ARG:-}" ]; then
  echo "[2S2H] No mm.o2r after extraction; launching with the ROM so 2S2H can surface the issue."
  exec "$BIN" "$S2H_ROM_ARG"
else
  echo "[2S2H] Launching 2 Ship 2 Harkinian."
  exec "$BIN"
fi
