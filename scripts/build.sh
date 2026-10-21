#!/usr/bin/env bash
# Builds the JS core, copies it into the Swift package's resources, then builds the Mac app.
#
#   scripts/build.sh              debug build (.build/debug/LectureStudio)
#   scripts/build.sh -c release   release build
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root/web-core"
# Install when node_modules is missing or older than the lock file (a dependency was added).
[ node_modules/.package-lock.json -nt package-lock.json ] || npm install --no-audit --no-fund
npm run build
res="$root/Sources/LectureStudio/Resources"
mkdir -p "$res/themes"
cp dist/studio-preview.js dist/studio-editor.js dist/studio-agent.js "$res/"
cp dist/themes/*.css "$res/themes/"
cd "$root"
swift build "$@"
