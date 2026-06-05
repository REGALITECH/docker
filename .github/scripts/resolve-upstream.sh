#!/usr/bin/env bash
# resolve-upstream.sh — DETERMINISTIC upstream-version resolver (NO AI).
#
# Reads the committed ARG pin from <image>/Dockerfile, queries the per-image
# upstream datasource, and emits to $GITHUB_OUTPUT:
#   current=<pinned version>
#   latest=<resolved newest version within the tracked major>
#   is_newer=<true|false>
#   classification_hint=<patch|minor|major|unknown>
#   notes_url=<release-notes / changelog URL for the latest version>
#
# It also writes the fetched release-notes / advisory text to a file path given
# by $NOTES_FILE (default ./upstream-notes.md) so the AI step can consume it.
#
# WHY deterministic: the AI step must NEVER invent a version number. Resolution
# (the part that must be exact) is pure bash + curl + jq here; the AI only does
# judgement work (adapt the Dockerfile recipe, classify, triage) downstream.
#
# Usage: resolve-upstream.sh <image>
#   <image> in {rtpengine, asterisk}
#   (kamailio = rolling apt branch, ari-proxy = pinned fork commit — both are
#    NOT version-tracked here; they are covered by rebuild-from-pins.yml.)
#
# Auth: set GH_TOKEN (or GITHUB_TOKEN) to raise the GitHub API rate limit.
set -euo pipefail

IMAGE="${1:?usage: resolve-upstream.sh <image>}"
REPO_ROOT="${GITHUB_WORKSPACE:-$(cd "$(dirname "$0")/../.." && pwd)}"
DOCKERFILE="${REPO_ROOT}/${IMAGE}/Dockerfile"
NOTES_FILE="${NOTES_FILE:-${REPO_ROOT}/upstream-notes.md}"
OUT="${GITHUB_OUTPUT:-/dev/stdout}"

[ -f "$DOCKERFILE" ] || { echo "::error::no Dockerfile at $DOCKERFILE" >&2; exit 1; }

# curl with the GitHub token if present (raises rate limit; not required).
gh_curl() {
  local url="$1"
  local token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
  if [ -n "$token" ]; then
    curl -fsSL -H "Authorization: Bearer ${token}" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" "$url"
  else
    curl -fsSL -H "Accept: application/vnd.github+json" "$url"
  fi
}

# read_arg <ARG_NAME> — extract the default value of `ARG <NAME>=<value>`.
read_arg() {
  grep -E "^ARG ${1}=" "$DOCKERFILE" | head -n1 | sed -E "s/^ARG ${1}=//" | tr -d '[:space:]'
}

# emit <key> <value>
emit() { printf '%s=%s\n' "$1" "$2" >> "$OUT"; }

: > "$NOTES_FILE"

case "$IMAGE" in
  rtpengine)
    # Datasource: GitHub tags sipwise/rtpengine. Strict stable regex
    # ^mr[0-9]+(\.[0-9]+)+$ excludes pre/RC tags. Sort by version, take newest.
    CURRENT="$(read_arg RTPENGINE_VERSION)"
    TAGS_JSON="$(gh_curl 'https://api.github.com/repos/sipwise/rtpengine/tags?per_page=100')"
    LATEST="$(printf '%s' "$TAGS_JSON" \
      | jq -r '.[].name' \
      | grep -E '^mr[0-9]+(\.[0-9]+)+$' \
      | sed 's/^mr//' \
      | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n \
      | tail -n1)"
    LATEST="mr${LATEST}"
    NOTES_URL="https://github.com/sipwise/rtpengine/releases/tag/${LATEST}"
    # Fetch release-notes body (best effort).
    gh_curl "https://api.github.com/repos/sipwise/rtpengine/releases/tags/${LATEST}" 2>/dev/null \
      | jq -r '.body // ""' >> "$NOTES_FILE" || true
    CUR_NUM="${CURRENT#mr}"; NEW_NUM="${LATEST#mr}"
    ;;

  asterisk)
    # Datasource: GitHub releases asterisk/asterisk. Track within major 23:
    # regex ^23\.[0-9]+\.[0-9]+$ AND prerelease==false (CRITICAL — exclude
    # 23.x-rc1 prereleases). Then verify the tarball exists upstream.
    CURRENT="$(read_arg ASTERISK_VERSION)"
    MAJOR="${CURRENT%%.*}"
    REL_JSON="$(gh_curl "https://api.github.com/repos/asterisk/asterisk/releases?per_page=100")"
    LATEST="$(printf '%s' "$REL_JSON" \
      | jq -r --arg M "$MAJOR" \
          '.[] | select(.prerelease==false) | .tag_name
           | select(test("^" + $M + "\\.[0-9]+\\.[0-9]+$"))' \
      | sort -t. -k1,1n -k2,2n -k3,3n \
      | tail -n1)"
    [ -n "$LATEST" ] || { echo "::error::no GA asterisk ${MAJOR}.x release found" >&2; exit 1; }
    # Verify the tarball actually exists before declaring a bump valid.
    TARBALL="https://downloads.asterisk.org/pub/telephony/asterisk/releases/asterisk-${LATEST}.tar.gz"
    if ! curl -fsIL "$TARBALL" >/dev/null 2>&1; then
      echo "::warning::resolved ${LATEST} but tarball missing at ${TARBALL}; holding at current" >&2
      LATEST="$CURRENT"
    fi
    NOTES_URL="https://github.com/asterisk/asterisk/releases/tag/${LATEST}"
    printf '%s' "$REL_JSON" \
      | jq -r --arg T "$LATEST" '.[] | select(.tag_name==$T) | .body // ""' >> "$NOTES_FILE" || true
    CUR_NUM="$CURRENT"; NEW_NUM="$LATEST"
    ;;

  *)
    echo "::error::image '$IMAGE' is not version-tracked (rolling/pinned-fork; see rebuild-from-pins.yml)" >&2
    exit 1
    ;;
esac

# Compare current vs latest (numeric dotted compare). is_newer = latest > current.
ver_gt() { # ver_gt A B  -> exit 0 if A > B
  [ "$1" = "$2" ] && return 1
  [ "$(printf '%s\n%s\n' "$1" "$2" | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n | tail -n1)" = "$1" ]
}

IS_NEWER=false
if ver_gt "$NEW_NUM" "$CUR_NUM"; then IS_NEWER=true; fi

# classification_hint: compare major/minor of the dotted numbers (mr-prefix
# already stripped into *_NUM). major changed -> "major"; minor changed ->
# "minor"; only patch changed -> "patch". The AI step makes the final call and
# also weighs CVE/advisory text; this is just a hint.
HINT=unknown
if [ "$IS_NEWER" = true ]; then
  cmaj="${CUR_NUM%%.*}"; nmaj="${NEW_NUM%%.*}"
  cmin="$(echo "$CUR_NUM" | cut -d. -f2)"; nmin="$(echo "$NEW_NUM" | cut -d. -f2)"
  if [ "$cmaj" != "$nmaj" ]; then HINT=major
  elif [ "$cmin" != "$nmin" ]; then HINT=minor
  else HINT=patch
  fi
fi

emit current "$CURRENT"
emit latest "$LATEST"
emit is_newer "$IS_NEWER"
emit classification_hint "$HINT"
emit notes_url "$NOTES_URL"

{
  echo "## ${IMAGE}: ${CURRENT} -> ${LATEST} (is_newer=${IS_NEWER}, hint=${HINT})"
  echo "Release notes: ${NOTES_URL}"
} >> "${GITHUB_STEP_SUMMARY:-/dev/stderr}"
