# Shared helpers for the SoH startup scripts. Sourced (as 'retro') by both
# /opt/gow/startup.d/10-soh-config.sh and /opt/soh/launch-soh.sh.
#
# Functions read these globals at call time: SHARED_DIR, SOH_VERSION, and the CWD (the home).
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

# Promote a freshly-generated oot.o2r/oot-mq.o2r that SoH wrote into the home (CWD) to the
# shared dir, drop the home copy, and stamp the version marker — but ONLY when something was
# actually promoted (no marker churn in steady state). No-op if the shared dir isn't writable.
# Run from the home dir (CWD). Safe under `set -e` (uses if/then, never bare &&).
promote_o2r() {
  [ -d "$SHARED_DIR" ] && [ -w "$SHARED_DIR" ] || return 0
  local f promoted=0
  for f in oot.o2r oot-mq.o2r; do
    if [ -f "$f" ] && [ ! -L "$f" ] && [ ! -e "$SHARED_DIR/$f" ]; then
      if publish_file "$f" "$SHARED_DIR/$f"; then rm -f "$f"; promoted=1; fi
    fi
  done
  if [ "$promoted" = 1 ]; then
    publish_string "${SOH_VERSION:-unknown}" "$SHARED_DIR/.soh-o2r-version" || true
  fi
}
