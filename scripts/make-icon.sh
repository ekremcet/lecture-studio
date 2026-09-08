#!/usr/bin/env bash
# Generates the app icon with OpenAI's gpt-image-2 and packs it into Packaging/AppIcon.icns.
# Reads OPENAI_API_KEY from the environment or from .env at the project root; the key is never printed.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/Packaging"
work="${TMPDIR:-/tmp}/lecture-studio-icon"
mkdir -p "$out" "$work"
if [ -z "${OPENAI_API_KEY:-}" ] && [ -f "$root/.env" ]; then
  OPENAI_API_KEY="$(grep -E '^OPENAI_(API_)?KEY=' "$root/.env" | head -1 | cut -d= -f2- | tr -d '"'"'"' ')"
fi
export OPENAI_API_KEY
[ -n "${OPENAI_API_KEY:-}" ] || { echo "OPENAI_API_KEY is not set (environment or .env)" >&2; exit 1; }

prompt="${ICON_PROMPT:-A macOS app icon for 'Lecture Studio', an app where teachers and speakers write slide decks from their reading sources. Squircle rounded-square icon, front view, one bold flat illustration: a single presentation slide (16:9 white card with a thin dark title bar and two soft text lines) leaning on a small stack of two closed books, with a faint speech-bubble spark above the slide. Deep indigo-to-teal gradient background, subtle top-left light, clean vector look, generous margins, no text, no letters, no watermark, centered, high contrast, Apple Human Interface style.}"

if [ "${REUSE:-}" = "1" ] && [ -f "$work/icon-1024.png" ]; then echo "reusing $work/icon-1024.png"; else
python3 - "$prompt" "$work" <<'PY'
import json, os, sys, urllib.request, base64
prompt, work = sys.argv[1], sys.argv[2]
req = urllib.request.Request(
    "https://api.openai.com/v1/images/generations",
    data=json.dumps({"model": "gpt-image-2", "prompt": prompt, "size": "1024x1024", "quality": "high", "n": 1, "background": "opaque", "output_format": "png"}).encode(),
    headers={"Authorization": "Bearer " + os.environ["OPENAI_API_KEY"], "Content-Type": "application/json"},
)
try:
    with urllib.request.urlopen(req, timeout=300) as r:
        body = json.load(r)
except urllib.error.HTTPError as e:
    detail = e.read().decode(errors="replace")
    sys.exit(f"image request failed: HTTP {e.code}: {detail[:600]}")
item = body["data"][0]
if "b64_json" in item:
    png = base64.b64decode(item["b64_json"])
else:
    png = urllib.request.urlopen(item["url"], timeout=120).read()
open(os.path.join(work, "icon-1024.png"), "wb").write(png)
print("generated", len(png), "bytes", "revised:", item.get("revised_prompt", "")[:200])
PY
fi

# The model draws the squircle on a white ground; clip it so the corners are transparent.
swift "$root/scripts/mask-icon.swift" "$work/icon-1024.png" "$work/icon-1024-masked.png"
set="$work/AppIcon.iconset"
rm -rf "$set"; mkdir -p "$set"
src="$work/icon-1024-masked.png"
for size in 16 32 128 256 512; do
  sips -z $size $size "$src" --out "$set/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z $double $double "$src" --out "$set/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$set" -o "$out/AppIcon.icns"
cp "$src" "$out/AppIcon-1024.png"
echo "wrote $out/AppIcon.icns and AppIcon-1024.png"
