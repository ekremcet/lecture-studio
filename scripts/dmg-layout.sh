#!/usr/bin/env bash
# Regenerates the disk image window layout (Packaging/dmg.DS_Store) with Finder: run it only when the
# layout changes (icon positions, window size, background). package.sh copies the saved file into every
# image, so the installer window is the same in every build and no Finder is involved at build time.
#
#   scripts/dmg-layout.sh [Packaging/dmg.DS_Store]
#
# Finder must lay out the actual "Lecture Studio" volume, so no other volume of that name may be mounted
# while this runs (a build made that way once shipped without a layout).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
target="${1:-$root/Packaging/dmg.DS_Store}"
work="$(mktemp -d)"
stage="$work/stage"
mkdir -p "$stage/.background" "$stage/Lecture Studio.app"
ln -s /Applications "$stage/Applications"
swift "$root/scripts/dmg-background.swift" "$stage/.background/background.png" 560 360 >/dev/null
rw="$work/layout.dmg"
hdiutil create -quiet -volname "Lecture Studio" -srcfolder "$stage" -ov -format UDRW -fs HFS+ "$rw"
mount="$(hdiutil attach -readwrite -noverify -noautoopen "$rw" | grep -o '/Volumes/.*$' | head -1)"
if [ "$mount" != "/Volumes/Lecture Studio" ]; then
  echo "error: the image mounted at '$mount', not '/Volumes/Lecture Studio'; eject the other Lecture Studio volume and run again" >&2
  hdiutil detach -quiet "$mount"; rm -rf "$work"; exit 1
fi
osascript <<'EOS'
tell application "Finder"
  tell disk "Lecture Studio"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set pathbar visible of container window to false
    set the bounds of container window to {200, 200, 760, 560}
    set theViewOptions to the icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 128
    set background picture of theViewOptions to file ".background:background.png"
    set position of item "Lecture Studio.app" of container window to {150, 170}
    set position of item "Applications" of container window to {410, 170}
    close
    open
    update without registering applications
    delay 1
    close
  end tell
end tell
EOS
# Finder writes .DS_Store on its own schedule.
for _ in $(seq 1 30); do [ -f "$mount/.DS_Store" ] && break; sleep 0.5; done
sync
[ -f "$mount/.DS_Store" ] || { echo "error: Finder wrote no .DS_Store" >&2; hdiutil detach -quiet "$mount"; rm -rf "$work"; exit 1; }
cp "$mount/.DS_Store" "$target"
hdiutil detach -quiet "$mount"
rm -rf "$work"
echo "wrote $target"
