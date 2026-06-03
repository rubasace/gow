# Shared helpers for the Ghostship startup scripts. Sourced (as 'retro') by both
# /opt/gow/startup.d/10-ghostship-config.sh and /opt/ghostship/launch-ghostship.sh.
#
# Functions read these globals at call time: SHARED_DIR, GHOSTSHIP_VERSION, and the CWD (the
# home). Pure helpers (no logging, no shell-option changes) so they're safe under the caller's
# `set`.

# Atomic publish to the shared dir: write to a unique temp in the SAME dir, then rename
# (atomic on one filesystem). A concurrent session never sees a half-written file, and two
# simultaneous publishes each land a COMPLETE file (last rename wins; both are valid).
publish_file() { # <src> <dest>
  local tmp; tmp="$(mktemp "$2.XXXXXX" 2>/dev/null)" || return 1
  if cp -f "$1" "$tmp" 2>/dev/null && mv -f "$tmp" "$2" 2>/dev/null; then return 0; fi
  rm -f "$tmp" 2>/dev/null; return 1
}
publish_string() { # <string> <dest>
  local tmp; tmp="$(mktemp "$2.XXXXXX" 2>/dev/null)" || return 1
  if printf '%s\n' "$1" > "$tmp" 2>/dev/null && mv -f "$tmp" "$2" 2>/dev/null; then return 0; fi
  rm -f "$tmp" 2>/dev/null; return 1
}

# Promote a freshly-generated sm64.o2r that lives in the home (CWD) to the shared dir, drop the
# home copy, and stamp the version marker — but ONLY when something was actually promoted (no
# marker churn in steady state). No-op if the shared dir isn't writable. Run from the home dir.
# Safe under `set -e` (uses if/then, never bare &&). SM64 has a single ROM archive.
promote_o2r() {
  [ -d "$SHARED_DIR" ] && [ -w "$SHARED_DIR" ] || return 0
  local f promoted=0
  for f in sm64.o2r; do
    if [ -f "$f" ] && [ ! -L "$f" ] && [ ! -e "$SHARED_DIR/$f" ]; then
      if publish_file "$f" "$SHARED_DIR/$f"; then rm -f "$f"; promoted=1; fi
    fi
  done
  if [ "$promoted" = 1 ]; then
    publish_string "${GHOSTSHIP_VERSION:-unknown}" "$SHARED_DIR/.ghostship-o2r-version" || true
  fi
}

# --- Headless first-run extraction (Super Mario 64) ------------------------------------------
# Ghostship has no headless ROM->sm64.o2r path on Linux: with no sm64.o2r it draws a blocking
# ImGui "Generate one now?" popup and then a zenity/kdialog file picker base-app doesn't ship —
# none of which a Moonlight gamepad can drive — and the release bundles no extractor binary
# (Torch is compiled into the game, not shipped as a CLI). So we build sm64.o2r ourselves with
# the standalone Torch CLI baked into this image (built from the EXACT commit Ghostship pins for
# this version, so it matches config.yml / the asset YAMLs in the bundle). This mirrors
# Ghostship's own internal call (Companion: srcDir = bundle, dest = data dir): Torch reads
# config.yml, keys on the ROM's sha1 to pick the US/JP asset set, and writes output.binary
# (sm64.o2r) into the dest dir. Fully headless.

TORCH_BIN=/opt/ghostship/torch
TORCH_SRC=/opt/ghostship/usr/bin   # Ghostship's GetAppBundlePath(): holds config.yml + assets/

rom_sha1() { sha1sum "$1" 2>/dev/null | cut -d' ' -f1; }

# Ghostship supports exactly two dumps (config.yml / readme.txt): US and JP, in .z64 format.
rom_supported() { # <rom>
  case "$(rom_sha1 "$1")" in
    9bef1128717f958171a4afac3ed78ee2bb4e86ce) return 0 ;;  # Super Mario 64 (US)
    8a20a5c83d6ceb0f0506cfc9fa20d8f438cafe51) return 0 ;;  # Super Mario 64 (JP)
    *) return 1 ;;
  esac
}

# Build sm64.o2r from a ROM with the standalone Torch. srcdir = the read-only bundle (config.yml
# + assets/ymls/<ver>), exactly as the in-app extractor uses it, so it never writes there. We run
# Torch into a tempdir and publish the result atomically. Torch's output streams to the caller's
# stdout/stderr (the container logs) — nothing is written to the user's home. Bounded by
# `timeout`. Returns 0 on success, 1 on any failure.
torch_extract() { # <rom-abs> <dest>
  local rom="$1" dest="$2" td rc
  [ -x "$TORCH_BIN" ] && [ -f "$TORCH_SRC/config.yml" ] || return 1
  td="$(mktemp -d 2>/dev/null)" || return 1
  # No -u/--version: that flag isn't on the o2r subcommand in every Torch revision Ghostship has
  # pinned, and the version stamp is optional metadata for the ROM archive. Torch keys the asset
  # set on the ROM's sha1 via config.yml regardless.
  ( cd "$td" && timeout 900 "$TORCH_BIN" o2r "$rom" -s "$TORCH_SRC" -d "$td" )
  rc=$?
  if [ "$rc" = 0 ] && [ -s "$td/sm64.o2r" ] && publish_file "$td/sm64.o2r" "$dest"; then
    rm -rf "$td"; return 0
  fi
  rm -rf "$td"; return 1
}
