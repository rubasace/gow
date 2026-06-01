#!/usr/bin/env bash
# Runs inside the compositor (gow `launcher`), as user retro.
#
# Data model (three places):
#   - GAME_DIR   (/opt/soh/usr/bin)  read-only baked files: binary, soh.o2r, assets.
#   - WORK_DIR   ($HOME/soh)         PER-USER: Wolf auto-mounts the home per profile;
#                                    SoH writes settings + saves here (persist per user).
#   - SHARED_DIR (/mnt/soh-shared)   SHARED bind mount you provide: the ROM (.z64) and
#                                    the COMMON oot.o2r reused by every profile.
#
# We keep the CWD in WORK_DIR (so settings/saves stay per-user) and symlink the shared
# ROM + common oot.o2r into it. If there's no common oot.o2r yet, SoH generates one from
# the ROM this session and we promote it to SHARED_DIR so the next launch (and other
# profiles) reuse it.
set -euo pipefail

GAME_DIR=/opt/soh/usr/bin
BIN="$GAME_DIR/soh.elf"
WORK_DIR="${SOH_HOME:-$HOME/soh}"          # per-user (Wolf home)
SHARED_DIR="${SOH_SHARED:-/mnt/soh-shared}" # shared mount: ROM + common oot.o2r
MARKER="$SHARED_DIR/.soh-o2r-version"       # SoH version that generated the shared oot.o2r
IMAGE_VER="${SOH_VERSION:-unknown}"

log() { echo "[SoH] $*"; }
major() { printf '%s' "${1%%.*}"; }

mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# Read-only baked files -> CWD.
ln -sfn "$GAME_DIR/assets" assets
ln -sf  "$GAME_DIR/soh.o2r" soh.o2r
if [ -f "$GAME_DIR/gamecontrollerdb.txt" ]; then
  ln -sf "$GAME_DIR/gamecontrollerdb.txt" gamecontrollerdb.txt
fi

# Shared ROM -> CWD (SoH validates by hash; only used if there's no oot.o2r yet).
have_rom=0
if [ -d "$SHARED_DIR" ]; then
  shopt -s nullglob
  for rom in "$SHARED_DIR"/*.z64 "$SHARED_DIR"/*.n64 "$SHARED_DIR"/*.zip; do
    ln -sf "$rom" "./$(basename "$rom")"
    have_rom=1
  done
  shopt -u nullglob
fi

# Promote a per-user-generated oot.o2r to the shared dir so it becomes common.
if [ -d "$SHARED_DIR" ] && [ ! -e "$SHARED_DIR/oot.o2r" ] && [ -f oot.o2r ] && [ ! -L oot.o2r ] && [ -w "$SHARED_DIR" ]; then
  log "Promoviendo el oot.o2r generado al directorio compartido."
  cp -f oot.o2r "$SHARED_DIR/oot.o2r"
  if [ -f oot-mq.o2r ] && [ ! -L oot-mq.o2r ]; then cp -f oot-mq.o2r "$SHARED_DIR/oot-mq.o2r"; fi
  printf '%s\n' "$IMAGE_VER" > "$MARKER" 2>/dev/null || true
fi

# Prefer the shared (common) oot.o2r: symlink it into CWD, dropping any per-user copy.
if [ -e "$SHARED_DIR/oot.o2r" ]; then
  rm -f oot.o2r oot-mq.o2r
  ln -sf "$SHARED_DIR/oot.o2r" oot.o2r
  if [ -e "$SHARED_DIR/oot-mq.o2r" ]; then ln -sf "$SHARED_DIR/oot-mq.o2r" oot-mq.o2r; fi
  # Version check (warn only: the shared o2r is yours to manage; not auto-deleted).
  if [ -f "$MARKER" ]; then
    stored="$(cat "$MARKER" 2>/dev/null || echo unknown)"
    if [ "$(major "$stored")" != "$(major "$IMAGE_VER")" ]; then
      log "AVISO: el oot.o2r compartido es de otra version MAYOR ($stored vs $IMAGE_VER)."
      log "       Refrescalo: borra $SHARED_DIR/oot.o2r y arranca con la ROM presente, o reemplazalo."
    fi
  fi
elif [ "$have_rom" = 1 ]; then
  log "No hay oot.o2r comun: SoH lo generara desde la ROM (veras 'Processing OTR') y lo promociono luego."
else
  log "ERROR: no hay oot.o2r comun ni ROM en $SHARED_DIR."
  log "       Copia tu ROM (OoT NTSC 1.0 US, .z64) o un oot.o2r ya generado a la carpeta compartida."
fi

log "Arrancando Ship of Harkinian $IMAGE_VER (CWD=$WORK_DIR, shared=$SHARED_DIR)"
exec "$BIN" "$@"
