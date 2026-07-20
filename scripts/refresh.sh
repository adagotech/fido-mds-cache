#!/usr/bin/env bash
#
# Download the FIDO Alliance MDS blob, verify it, and compare its nextUpdate date
# against the one recorded in next-update.txt. If they differ, next-update.txt is
# rewritten and a "changed=true" output is emitted for the CI pipeline to act on.
#
# The downloaded blob is written to blob.jwt at the repo root so the Docker build
# can COPY it from the build context instead of downloading it a second time
# (a second request can trip the upstream 429 rate limit this cache exists to
# avoid). blob.jwt is gitignored and never committed.
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
BLOB_FILE="$ROOT/blob.jwt"

meta_json="$(mktemp)"
trap 'rm -f "$meta_json"' EXIT

echo "Downloading blob from $BLOB_URL ..."
curl -fsSL --retry 5 --retry-delay 10 "$BLOB_URL" -o "$BLOB_FILE"

# A JWT is three base64url segments separated by dots.
test -s "$BLOB_FILE" || { echo "ERROR: downloaded file is empty" >&2; exit 1; }
[ "$(tr -cd '.' < "$BLOB_FILE" | wc -c)" -eq 2 ] || {
    echo "ERROR: downloaded file does not look like a JWT" >&2; exit 1; }

# Decode the JWT payload (second segment) from base64url to JSON. The payload can
# be many megabytes, so this streams through `tr` rather than using bash string
# substitution (which is pathologically slow on large strings).
b64="$(cut -d. -f2 "$BLOB_FILE" | tr -d '\n' | tr '_-' '/+')"
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
