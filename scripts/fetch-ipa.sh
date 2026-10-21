#!/usr/bin/env bash
# Downloads the newest encrypted IPA built on main, decrypts it with the local
# age key, then deletes the artifact from GitHub (see docs/sideloading.md).
set -euo pipefail

KEY="${CLOUDROLL_IPA_KEY:-$HOME/.config/cloudroll/ipa-key.txt}"
OUT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/build"
ARTIFACT=cloudroll-ipa-encrypted

[[ -r "$KEY" ]] || { echo "Decryption key not found at $KEY" >&2; exit 1; }
command -v age >/dev/null || { echo "age is not installed: omarchy pkg add age" >&2; exit 1; }

# Pick the newest successful run first: the artifact listing can briefly still
# show artifacts that were already deleted.
run_id="$(gh run list --workflow ios.yml --branch main --event push --status success --limit 1 \
  --json databaseId -q '.[0].databaseId')"
[[ -n "$run_id" ]] || { echo "No successful CI run on main yet" >&2; exit 1; }
artifact_id="$(gh api "repos/{owner}/{repo}/actions/runs/$run_id/artifacts" \
  --jq "[.artifacts[] | select(.name == \"$ARTIFACT\" and (.expired | not))][0].id // empty")"
[[ -n "$artifact_id" ]] || { echo "The newest build (CI run $run_id) was already fetched or has expired." >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
gh run download "$run_id" --name "$ARTIFACT" --dir "$tmp"

mkdir -p "$OUT_DIR"
age -d -i "$KEY" -o "$OUT_DIR/Cloudroll.ipa" "$tmp/Cloudroll-unsigned.ipa.age"
gh api -X DELETE "repos/{owner}/{repo}/actions/artifacts/$artifact_id"
version="$(unzip -p "$OUT_DIR/Cloudroll.ipa" Payload/Cloudroll.app/Info.plist \
  | python3 -I -c 'import plistlib, sys; print(plistlib.loads(sys.stdin.buffer.read())["CFBundleShortVersionString"])')"
echo "Decrypted Cloudroll $version (CI run $run_id) to $OUT_DIR/Cloudroll.ipa and deleted it from GitHub."
