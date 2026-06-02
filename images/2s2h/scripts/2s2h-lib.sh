# Shared helpers for the 2S2H startup scripts. Sourced (as 'retro') by both
# /opt/gow/startup.d/10-2s2h-config.sh and /opt/2s2h/launch-2s2h.sh.
#
# Functions read these globals at call time: SHARED_DIR, S2H_VERSION, and the CWD (the home).
# Pure helpers (no logging, no shell-option changes) so they're safe under the caller's `set`.

fsize() { stat -c%s "$1" 2>/dev/null || stat -f%z "$1" 2>/dev/null || echo 0; }

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

# Promote a freshly-generated mm.o2r that lives in the home (CWD) to the shared dir, drop the
# home copy, and stamp the version marker — but ONLY when something was actually promoted (no
# marker churn in steady state). No-op if the shared dir isn't writable. Run from the home dir.
# Safe under `set -e` (uses if/then, never bare &&). MM has no Master Quest -> single archive.
promote_o2r() {
  [ -d "$SHARED_DIR" ] && [ -w "$SHARED_DIR" ] || return 0
  local f promoted=0
  for f in mm.o2r; do
    if [ -f "$f" ] && [ ! -L "$f" ] && [ ! -e "$SHARED_DIR/$f" ]; then
      if publish_file "$f" "$SHARED_DIR/$f"; then rm -f "$f"; promoted=1; fi
    fi
  done
  if [ "$promoted" = 1 ]; then
    publish_string "${S2H_VERSION:-unknown}" "$SHARED_DIR/.2s2h-o2r-version" || true
  fi
}

# --- Headless first-run extraction (Majora's Mask) -------------------------------------------
# 2S2H 4.0.2's in-app extractor (InitOTR) is GUI-gated: with no mm.o2r it ALWAYS pops a blocking
# SDL "Generate one now?" box, and if no ROM sits in its search dir it opens a zenity/kdialog
# file picker that base-app doesn't ship. None of that can be driven by a Moonlight gamepad, and
# the argv-based RunExtract path SoH relies on is dead code here. So we bypass the app entirely
# and build mm.o2r ourselves with the SAME ZAPD invocation the app uses internally
# (Extractor::CallZapd), via the standalone ZAPD CLI shipped in the bundle. Fully headless.

ZAPD_BIN=/opt/2s2h/usr/bin/assets/extractor/ZAPD.out
ZAPD_ASSETS=/opt/2s2h/usr/bin/assets
ZAPD_LIBS=/opt/2s2h/usr/lib

rom_sha1() { sha1sum "$1" 2>/dev/null | cut -d' ' -f1; }

# Map a ROM to ZAPD's version id (mirrors Extractor::GetZapdVerStr). 2S2H supports exactly two
# dumps: NTSC-U GC -> GC_US; NTSC-U 1.0 (and anything else we attempt) -> N64_US. The GC sha1 is
# matched exactly; an unmatched hash defaults to N64_US and ZAPD decides if it's actually valid.
detect_zapd_ver() { # <rom>
  case "$(rom_sha1 "$1")" in
    9743aa026e9269b339eb0e3044cd5830a440c1fd) echo GC_US ;;
    *) echo N64_US ;;
  esac
}

# Build mm.o2r from a ROM with the standalone ZAPD, mirroring Extractor::CallZapd verbatim: cd
# into a tempdir with `assets` symlinked, run with relative -i/-rconf/-fl and --otrfile mm.o2r,
# then publish the result to <dest> atomically. Returns 0 on success, 1 on any failure. All ZAPD
# output is captured to <logfile> so a failed run is diagnosable. Bounded by `timeout`.
zapd_extract() { # <rom-abs> <ver> <dest> <logfile>
  local rom="$1" ver="$2" dest="$3" logfile="$4" td rc
  [ -x "$ZAPD_BIN" ] && [ -d "$ZAPD_ASSETS/xml/$ver" ] || return 1
  td="$(mktemp -d 2>/dev/null)" || return 1
  ln -sfn "$ZAPD_ASSETS" "$td/assets"
  ( cd "$td" && LD_LIBRARY_PATH="$ZAPD_LIBS:${LD_LIBRARY_PATH:-}" \
      timeout 600 "$ZAPD_BIN" ed \
        -i "assets/xml/$ver" -b "$rom" -fl assets/filelists -gsf 0 \
        -rconf "assets/Config_$ver.xml" -se OTR --otrfile mm.o2r \
        --portVer "${S2H_VERSION:-0.0.0}" -o placeholder -osf placeholder \
  ) >"$logfile" 2>&1
  rc=$?
  if [ "$rc" = 0 ] && [ -s "$td/mm.o2r" ] && publish_file "$td/mm.o2r" "$dest"; then
    rm -rf "$td"; return 0
  fi
  rm -rf "$td"; return 1
}
