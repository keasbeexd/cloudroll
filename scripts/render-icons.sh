#!/usr/bin/env bash
# Renders the app icons in design/icons/ into the asset catalog: the main icon set
# (with its dark and tinted appearances), one icon set per alternate icon, and a small
# preview image of each for the icon picker in Settings. Needs rsvg-convert (librsvg).
# The rendered PNGs are committed, so CI doesn't need this.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/design/icons"
OUT="$ROOT/src/Assets.xcassets"

# Alternate icons: asset name and source file. Keep in sync with AppIcon in AppIconPicker.swift.
ALTERNATES=(
  "Sunset:sunset" "Sky:sky" "Noir:noir" "Lens:lens" "Outline:outline"
  "Film:film" "Aperture:aperture" "GoldenHour:golden" "Instant:instant" "Grid:grid"
)

command -v rsvg-convert >/dev/null || { echo "rsvg-convert is not installed (librsvg)" >&2; exit 1; }

render() { rsvg-convert -w "$2" -h "$2" "$SRC/$1.svg" -o "$3"; }

catalog_info='"info" : { "author" : "xcode", "version" : 1 }'

mkdir -p "$OUT"
echo "{ $catalog_info }" >"$OUT/Contents.json"

main="$OUT/AppIcon.appiconset"
rm -rf "$main" && mkdir -p "$main"
render default 1024 "$main/AppIcon.png"
render dark 1024 "$main/AppIcon-Dark.png"
render tinted 1024 "$main/AppIcon-Tinted.png"
cat >"$main/Contents.json" <<EOF
{
  "images" : [
    { "filename" : "AppIcon.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" },
    { "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ],
      "filename" : "AppIcon-Dark.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" },
    { "appearances" : [ { "appearance" : "luminosity", "value" : "tinted" } ],
      "filename" : "AppIcon-Tinted.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" }
  ],
  $catalog_info
}
EOF

preview() {
  local set="$OUT/IconPreview-$1.imageset"
  rm -rf "$set" && mkdir -p "$set"
  render "$2" 180 "$set/IconPreview-$1.png"
  cat >"$set/Contents.json" <<EOF
{
  "images" : [ { "filename" : "IconPreview-$1.png", "idiom" : "universal", "scale" : "3x" } ],
  $catalog_info
}
EOF
}

preview Default default
for entry in "${ALTERNATES[@]}"; do
  name="${entry%%:*}" file="${entry##*:}"
  set="$OUT/AppIcon-$name.appiconset"
  rm -rf "$set" && mkdir -p "$set"
  render "$file" 1024 "$set/AppIcon-$name.png"
  cat >"$set/Contents.json" <<EOF
{
  "images" : [ { "filename" : "AppIcon-$name.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" } ],
  $catalog_info
}
EOF
  preview "$name" "$file"
done

echo "Rendered $(( ${#ALTERNATES[@]} + 1 )) icons into $OUT"
