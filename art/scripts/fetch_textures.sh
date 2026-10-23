#!/usr/bin/env bash
# Downloads CC0 texture sets from Poly Haven (polyhaven.com; CC0, no attribution needed) into
# art/textures/<id>/<id>_{diff,nor_gl,rough}_1k.jpg. Usage: bash art/scripts/fetch_textures.sh id [id ...]
# The textures used by victorian.py:
#   distressed_painted_planks roof_slates_02 mossy_stone_wall dark_brick_wall weathered_planks
#   dark_wooden_planks wood_shutter weathered_plank_siding wood_peeling_paint_weathered
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)/textures"
ua="TorT-texture-fetch/1.0"
for id in "$@"; do
  mkdir -p "$root/$id"
  json="$(curl -s -A "$ua" "https://api.polyhaven.com/files/$id")"
  for pair in Diffuse:diff nor_gl:nor_gl Rough:rough; do
    key=${pair%%:*}; short=${pair##*:}
    out="$root/$id/${id}_${short}_1k.jpg"
    [ -f "$out" ] && continue
    url="$(printf '%s' "$json" | python -I -c "import json,sys; d=json.load(sys.stdin); print(d.get(sys.argv[1],{}).get('1k',{}).get('jpg',{}).get('url',''))" "$key")"
    [ -n "$url" ] && curl -s -A "$ua" "$url" -o "$out" && echo "$id: $(basename "$out")"
  done
done
