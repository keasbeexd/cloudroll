#!/usr/bin/env bash
# Usage: scripts/fetch-ipa.sh [run-id]
# Downloads the newest (or the given run's) encrypted IPA built on main, decrypts it with the local
# age key, uploads it to Nextcloud for installing from the phone, then deletes
# the artifact from GitHub (see docs/sideloading.md).
set -euo pipefail

KEY="${CLOUDROLL_IPA_KEY:-$HOME/.config/cloudroll/ipa-key.txt}"
# Kept outside synced folders: desktop sync clients can lag or miss rewritten files.
OUT_DIR="${CLOUDROLL_BUILD_DIR:-$HOME/.cache/cloudroll/builds}"
NETRC="${CLOUDROLL_NEXTCLOUD_NETRC:-$HOME/.config/nc-keasbee.netrc}"
REMOTE_DIR="${CLOUDROLL_NEXTCLOUD_DIR:-Cloudroll Builds}"
ARTIFACT=cloudroll-ipa-encrypted

[[ -r "$KEY" ]] || { echo "Decryption key not found at $KEY" >&2; exit 1; }
[[ -r "$NETRC" ]] || { echo "Nextcloud credentials not found at $NETRC" >&2; exit 1; }
command -v age >/dev/null || { echo "age is not installed: omarchy pkg add age" >&2; exit 1; }

# Uploads the IPA into REMOTE_DIR on Nextcloud and removes older IPAs there.
upload_to_nextcloud() {
  local ipa="$1" host user dir url code
  host="$(awk '$1 == "machine" { print $2; exit }' "$NETRC")"
  user="$(awk '{ for (i = 1; i < NF; i++) if ($i == "login") { print $(i + 1); exit } }' "$NETRC")"
  [[ -n "$host" && -n "$user" ]] || { echo "Couldn't read machine/login from $NETRC" >&2; return 1; }
  dir="https://$host/remote.php/dav/files/$user/$(jq -rn --arg s "$REMOTE_DIR" '$s | @uri')"

  code="$(curl -sS --netrc-file "$NETRC" -X MKCOL -o /dev/null -w '%{http_code}' "$dir/")"
  [[ "$code" == 201 || "$code" == 405 ]] || { echo "Creating $REMOTE_DIR on Nextcloud failed (HTTP $code)" >&2; return 1; }

  for old in $(curl -sS --netrc-file "$NETRC" -X PROPFIND -H 'Depth: 1' "$dir/" | grep -oE '<d:href>[^<]+\.ipa</d:href>' | sed -E 's#</?d:href>##g'); do
    code="$(curl -sS --netrc-file "$NETRC" -X DELETE -o /dev/null -w '%{http_code}' "https://$host$old")"
    [[ "$code" == 204 ]] || { echo "Deleting old build $old failed (HTTP $code)" >&2; return 1; }
  done

  url="$dir/$(basename "$ipa")"
  code="$(curl -sS --netrc-file "$NETRC" -T "$ipa" -o /dev/null -w '%{http_code}' "$url")"
  [[ "$code" == 201 || "$code" == 204 ]] || { echo "Uploading to Nextcloud failed (HTTP $code)" >&2; return 1; }
}

# Pick the newest successful run first: the artifact listing can briefly still
# show artifacts that were already deleted.
# An explicit run ID avoids racing GitHub's run list, which can lag right after a run ends.
run_id="${1:-$(gh run list --workflow ios.yml --branch main --event push --status success --limit 1 \
  --json databaseId -q '.[0].databaseId')}"
[[ -n "$run_id" ]] || { echo "No successful CI run on main yet" >&2; exit 1; }
artifact_id="$(gh api "repos/{owner}/{repo}/actions/runs/$run_id/artifacts" \
  --jq "[.artifacts[] | select(.name == \"$ARTIFACT\" and (.expired | not))][0].id // empty")"
[[ -n "$artifact_id" ]] || { echo "The newest build (CI run $run_id) was already fetched or has expired." >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
gh run download "$run_id" --name "$ARTIFACT" --dir "$tmp"

age -d -i "$KEY" -o "$tmp/Cloudroll.ipa" "$tmp/Cloudroll-unsigned.ipa.age"
version="$(unzip -p "$tmp/Cloudroll.ipa" Payload/Cloudroll.app/Info.plist \
  | python3 -I -c 'import plistlib, sys; print(plistlib.loads(sys.stdin.buffer.read())["CFBundleShortVersionString"])')"

# A new name per build so the phone never opens a cached older copy;
# only the latest build is kept.
mkdir -p "$OUT_DIR"
find "$OUT_DIR" -maxdepth 1 -name 'Cloudroll*.ipa' -delete
ipa="$OUT_DIR/Cloudroll-$version-$(date +%Y%m%d-%H%M).ipa"
mv "$tmp/Cloudroll.ipa" "$ipa"

upload_to_nextcloud "$ipa"

# Delete this build and any older ones that were never fetched.
for id in $(gh api "repos/{owner}/{repo}/actions/artifacts?name=$ARTIFACT&per_page=100" --jq '.artifacts[].id'); do
  gh api -X DELETE "repos/{owner}/{repo}/actions/artifacts/$id"
done
echo "Cloudroll $version (CI run $run_id): saved to $ipa, uploaded to Nextcloud \"$REMOTE_DIR\", deleted from GitHub."
