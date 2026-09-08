#!/usr/bin/env bash
# Shrink an image to at most WIDTH px wide (default 1600), flatten transparency onto white.
#   resize.sh in.png out.png [WIDTH]
set -euo pipefail
in="$1"; out="$2"; w="${3:-1600}"
cmd=$(command -v magick || command -v convert || true)
if [ -z "$cmd" ]; then echo "ImageMagick not found; run: sudo apt-get install -y imagemagick" >&2; exit 1; fi
"$cmd" "$in" -resize "${w}x${w}>" -background white -alpha remove -alpha off "$out"
echo "wrote $out"
