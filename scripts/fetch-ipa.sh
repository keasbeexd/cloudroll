#!/usr/bin/env bash
# Downloads the newest encrypted IPA built on main, decrypts it with the local
# age key, then deletes the artifact from GitHub (see docs/sideloading.md).
set -euo pipefail

KEY="${CLOUDROLL_IPA_KEY:-$HOME/.config/cloudroll/ipa-key.txt}"
OUT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/build"
ARTIFACT=cloudroll-ipa-encrypted

[[ -r "$KEY" ]] || { echo "Decryption key not found at $KEY" >&2; exit 1; }
command -v age >/dev/null || { echo "age is not installed: omarchy pkg add age" >&2; exit 1; }

read -r artifact_id run_id < <(
  gh api "repos/{owner}/{repo}/actions/artifacts?name=$ARTIFACT" \
    --jq '[.artifacts[] | select(.expired | not) | select(.workflow_run.head_branch == "main")][0] | "\(.id) \(.workflow_run.id)"'
) || true
if [[ -z "${artifact_id:-}" || "$artifact_id" == "null" ]]; then
  echo "No build available: push to main and wait for CI, or the last one was already fetched." >&2
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
gh run download "$run_id" --name "$ARTIFACT" --dir "$tmp"

mkdir -p "$OUT_DIR"
age -d -i "$KEY" -o "$OUT_DIR/Cloudroll.ipa" "$tmp/Cloudroll-unsigned.ipa.age"
gh api -X DELETE "repos/{owner}/{repo}/actions/artifacts/$artifact_id"
version="$(unzip -p "$OUT_DIR/Cloudroll.ipa" Payload/Cloudroll.app/Info.plist \
  | python3 -I -c 'import plistlib, sys; print(plistlib.load(sys.stdin.buffer)["CFBundleShortVersionString"])')"
echo "Decrypted Cloudroll $version (CI run $run_id) to $OUT_DIR/Cloudroll.ipa and deleted it from GitHub."
