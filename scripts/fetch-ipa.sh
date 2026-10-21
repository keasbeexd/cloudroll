#!/usr/bin/env bash
# Downloads the encrypted IPA from the latest successful CI run on main and
# decrypts it with the local age key, for sideloading (see docs/sideloading.md).
set -euo pipefail

KEY="${CLOUDROLL_IPA_KEY:-$HOME/.config/cloudroll/ipa-key.txt}"
OUT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/build"
ARTIFACT=cloudroll-ipa-encrypted

[[ -r "$KEY" ]] || { echo "Decryption key not found at $KEY" >&2; exit 1; }
command -v age >/dev/null || { echo "age is not installed: omarchy pkg add age" >&2; exit 1; }

run_id="$(gh run list --branch main --status success --limit 1 --json databaseId -q '.[0].databaseId')"
[[ -n "$run_id" ]] || { echo "No successful CI run on main yet" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
gh run download "$run_id" --name "$ARTIFACT" --dir "$tmp"

mkdir -p "$OUT_DIR"
age -d -i "$KEY" -o "$OUT_DIR/Cloudroll.ipa" "$tmp/Cloudroll-unsigned.ipa.age"
echo "Decrypted build from CI run $run_id: $OUT_DIR/Cloudroll.ipa"
