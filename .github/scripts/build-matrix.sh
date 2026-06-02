#!/usr/bin/env bash
#
# Discover the buildable images under images/*/Dockerfile and emit a GitHub
# Actions build matrix. Adding a new image to the repository is zero-config:
# drop a folder under images/ with a Dockerfile and it is picked up here.
#
# Each image becomes one matrix entry: { name, context, version }
#   - name    : the image directory name == the GHCR repository name
#   - context : the Docker build context (the image directory itself)
#   - version : the upstream version pinned in the Dockerfile, read from the
#               `# renovate:`-annotated `ARG <APP>_VERSION=<value>` line.
#               Empty for images that have no single upstream pin (they get
#               only the rolling `edge` tag).
#
# WHICH images get included depends on the triggering event:
#   - schedule                       -> all images (keeps `edge` fresh vs base-app)
#   - workflow_dispatch (no input)   -> all images
#   - workflow_dispatch (images=...) -> just those (comma-separated names)
#   - push                           -> only images whose folder changed, or all
#                                       if a shared CI file (workflow/script) changed
#
# Inputs come from the environment so the script is runnable locally too:
#   GITHUB_EVENT_NAME, GITHUB_SHA, BEFORE_SHA, IMAGES_INPUT, GITHUB_OUTPUT
set -euo pipefail

event="${GITHUB_EVENT_NAME:-manual}"
before="${BEFORE_SHA:-}"
after="${GITHUB_SHA:-HEAD}"
images_input="${IMAGES_INPUT:-}"

list_all_dirs() {
  for dockerfile in images/*/Dockerfile; do
    [ -f "$dockerfile" ] || continue
    dirname "$dockerfile"
  done
}

# First `ARG <APP>_VERSION=<value>` immediately preceded by a `# renovate:` comment.
extract_version() {
  awk '
    /^[[:space:]]*#[[:space:]]*renovate:/ { pending = 1; next }
    pending && /^ARG[[:space:]]+[A-Za-z0-9_]*_VERSION=/ {
      line = $0
      sub(/^ARG[[:space:]]+[A-Za-z0-9_]*_VERSION=/, "", line)
      sub(/[[:space:]]+#.*/, "", line)   # strip any trailing inline comment
      sub(/\r$/, "", line)               # strip CR (CRLF files)
      gsub(/[[:space:]]+$/, "", line)
      print line
      exit
    }
    { pending = 0 }
  ' "$1"
}

changed_dirs() {
  # Image dirs touched between before..after; falls back to all images when the
  # base commit is unknown or a shared CI file changed.
  if [ -z "$before" ] \
     || [ "$before" = "0000000000000000000000000000000000000000" ] \
     || ! git cat-file -e "${before}^{commit}" 2>/dev/null; then
    list_all_dirs
    return
  fi
  local diff
  diff="$(git diff --name-only "$before" "$after")"
  if printf '%s\n' "$diff" | grep -qE '^\.github/(workflows|scripts)/'; then
    list_all_dirs
    return
  fi
  # `grep` legitimately matches nothing (e.g. a docs-only push); under pipefail
  # that would abort the script, so absorb a no-match into an empty result.
  { printf '%s\n' "$diff" \
      | grep -E '^images/[^/]+/' \
      | sed -E 's#^(images/[^/]+)/.*#\1#' \
      | sort -u \
      | while IFS= read -r d; do [ -f "$d/Dockerfile" ] && echo "$d"; done; } || true
}

# --- decide the target set (newline-separated dir list) ---
case "$event" in
  schedule)
    targets="$(list_all_dirs)" ;;
  workflow_dispatch)
    if [ -n "$images_input" ]; then
      targets=""
      IFS=',' read -r -a names <<< "$images_input"
      for n in "${names[@]}"; do
        n="$(printf '%s' "$n" | tr -d '[:space:]')"
        [ -n "$n" ] || continue
        if [ ! -f "images/$n/Dockerfile" ]; then
          echo "::error::Unknown image '$n' (no images/$n/Dockerfile). Available: $(list_all_dirs | xargs -n1 basename | paste -sd, -)" >&2
          exit 1
        fi
        targets="${targets}images/$n"$'\n'
      done
    else
      targets="$(list_all_dirs)"
    fi ;;
  push)
    targets="$(changed_dirs)" ;;
  *)
    targets="$(list_all_dirs)" ;;
esac

# --- build the matrix JSON ---
items='[]'
while IFS= read -r dir; do
  [ -n "$dir" ] || continue
  name="$(basename "$dir")"
  version="$(extract_version "$dir/Dockerfile" || true)"
  items="$(jq -c \
    --arg name "$name" \
    --arg context "$dir" \
    --arg version "$version" \
    '. + [{name: $name, context: $context, version: $version}]' <<< "$items")"
done <<< "$(printf '%s\n' "$targets" | sort -u)"

count="$(jq 'length' <<< "$items")"
matrix="$(jq -c '{include: .}' <<< "$items")"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "matrix=$matrix"
    echo "count=$count"
  } >> "$GITHUB_OUTPUT"
fi

echo "Discovered $count image(s) to build:" >&2
jq -r '.[] | "  - \(.name) (version: \(if .version == "" then "edge-only" else .version end))"' <<< "$items" >&2
echo "matrix=$matrix" >&2
