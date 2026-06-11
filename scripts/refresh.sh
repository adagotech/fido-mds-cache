#!/usr/bin/env bash
#
# Download the FIDO Alliance MDS blob, verify it, and compare its nextUpdate date
# against the one recorded in next-update.txt. If they differ, next-update.txt is
# rewritten and a "changed=true" output is emitted for the CI pipeline to act on.
#
# The blob itself is NOT kept (it is large and is rebuilt into the image by the
# Dockerfile). This script only exists to decide whether a rebuild is needed and
# to record the new nextUpdate date.
#
# Outputs (appended to $GITHUB_OUTPUT when set):
#   changed=true|false
#   next_update=<YYYY-MM-DD>   (only when changed)
#   blob_no=<serial>           (only when changed)
#
set -euo pipefail

BLOB_URL="${BLOB_URL:-https://mds.fidoalliance.org}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NEXT_UPDATE_FILE="$ROOT/next-update.txt"

TMP_BLOB="$(mktemp)"
trap 'rm -f "$TMP_BLOB"' EXIT

echo "Downloading blob from $BLOB_URL ..."
curl -fsSL --retry 5 --retry-delay 10 "$BLOB_URL" -o "$TMP_BLOB"

# A JWT is three base64url segments separated by dots.
test -s "$TMP_BLOB" || { echo "ERROR: downloaded file is empty" >&2; exit 1; }
[ "$(tr -cd '.' < "$TMP_BLOB" | wc -c)" -eq 2 ] || {
    echo "ERROR: downloaded file does not look like a JWT" >&2; exit 1; }

# Decode the JWT payload (second segment) from base64url to JSON. The payload can
# be many megabytes, so this streams through `tr` rather than using bash string
# substitution (which is pathologically slow on large strings).
meta_json="$(mktemp)"
trap 'rm -f "$TMP_BLOB" "$meta_json"' EXIT

b64="$(cut -d. -f2 "$TMP_BLOB" | tr -d '\n' | tr '_-' '/+')"
case $(( ${#b64} % 4 )) in
    2) b64="${b64}==";;
    3) b64="${b64}=";;
esac
printf '%s' "$b64" | base64 -d > "$meta_json"
unset b64

next_update="$(jq -r '.nextUpdate // empty' "$meta_json")"
blob_no="$(jq -r '.no // empty' "$meta_json")"

[ -n "$next_update" ] || { echo "ERROR: could not parse nextUpdate from blob" >&2; exit 1; }

current=""
[ -f "$NEXT_UPDATE_FILE" ] && current="$(tr -d '[:space:]' < "$NEXT_UPDATE_FILE")"

echo "Current nextUpdate: ${current:-<none>}"
echo "Upstream nextUpdate: $next_update (blob no=$blob_no)"

emit() { printf '%s\n' "$1" >> "${GITHUB_OUTPUT:-/dev/null}"; }

if [ "$current" = "$next_update" ]; then
    echo "Cache is up to date; nothing to do."
    emit "changed=false"
    exit 0
fi

echo "New blob detected; updating $NEXT_UPDATE_FILE"
printf '%s\n' "$next_update" > "$NEXT_UPDATE_FILE"
emit "changed=true"
emit "next_update=$next_update"
emit "blob_no=$blob_no"
