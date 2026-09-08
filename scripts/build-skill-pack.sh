#!/usr/bin/env bash
# Zip the Agent Plugins pack for upload to Oberik (or `pi install` later).
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p dist
rm -f dist/marp-slides.zip
(cd skill-pack && zip -qr ../dist/marp-slides.zip plugin.json skills -x '*.DS_Store')
unzip -l dist/marp-slides.zip | tail -1
