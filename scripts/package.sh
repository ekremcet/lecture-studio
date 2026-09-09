#!/usr/bin/env bash
# Builds LectureStudio.app for distribution outside the App Store: release build, .app bundle, Developer ID
# signature with the hardened runtime, DMG, notarization and stapling.
#
#   scripts/package.sh [version]
#
# Environment:
#   SIGN_IDENTITY      "Developer ID Application: Name (TEAMID)". Defaults to the first Developer ID identity,
#                      then to an Apple Development identity (local testing only; Gatekeeper rejects it elsewhere).
#   NOTARY_PROFILE     notarytool keychain profile (create once with `xcrun notarytool store-credentials <name>`).
#                      Without it the DMG is built and signed but not notarized.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
version="${1:-0.1.0}"
build="$(date +%Y%m%d%H%M)"
out="$root/dist"
app="$out/Lecture Studio.app"

"$root/scripts/build.sh" -c release >/dev/null
bin="$root/.build/release/LectureStudio"
bundle="$root/.build/release/LectureStudio_LectureStudio.bundle"

rm -rf "$out"; mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/LectureStudio"
cp -R "$bundle" "$app/Contents/Resources/"
sed -e "s/__VERSION__/$version/" -e "s/__BUILD__/$build/" "$root/Packaging/Info.plist" > "$app/Contents/Info.plist"
echo -n "APPL????" > "$app/Contents/PkgInfo"
[ ! -f "$root/Packaging/AppIcon.icns" ] || cp "$root/Packaging/AppIcon.icns" "$app/Contents/Resources/"
[ ! -f "$root/Packaging/AppIcon.icns" ] || /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$app/Contents/Info.plist"

find_identity() { security find-identity -v -p codesigning | grep -o "\"$1: [^\"]*\"" | head -1 | tr -d '"' || true; }
identity="${SIGN_IDENTITY:-$(find_identity "Developer ID Application")}"
if [ -z "$identity" ]; then
  identity="$(find_identity "Apple Development")"
  echo "warning: no Developer ID Application certificate; signing with '$identity' for local testing only" >&2
fi
codesign --force --deep --options runtime --timestamp --entitlements "$root/Packaging/entitlements.plist" --sign "$identity" "$app"
codesign --verify --strict --verbose=2 "$app"

# The disk image opens as the usual install window: the app on the left, a link to Applications on the
# right, an arrow between them on a drawn background. Finder lays the window out on a writable image
# (icon positions, view options, background live in its .DS_Store), which is then compressed.
dmg="$out/LectureStudio-$version.dmg"
stage="$out/dmg-stage"
rm -rf "$stage"; mkdir -p "$stage/.background"
cp -R "$app" "$stage/"
ln -s /Applications "$stage/Applications"
swift "$root/scripts/dmg-background.swift" "$stage/.background/background.png" 560 360 >/dev/null
rw="$out/LectureStudio-rw.dmg"
hdiutil create -quiet -volname "Lecture Studio" -srcfolder "$stage" -ov -format UDRW -fs HFS+ "$rw"
dev="$(hdiutil attach -readwrite -noverify -noautoopen "$rw" | grep -o '/dev/disk[0-9]*' | head -1)"
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
sync
hdiutil detach "$dev" -quiet
hdiutil convert -quiet "$rw" -format UDZO -o "$dmg" -ov
rm -f "$rw"; rm -rf "$stage"
codesign --force --timestamp --sign "$identity" "$dmg"

if [ -n "${NOTARY_PROFILE:-}" ]; then
  xcrun notarytool submit "$dmg" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$dmg"
  xcrun stapler staple "$app"
  spctl --assess --type open --context context:primary-signature -v "$dmg" || true
else
  echo "not notarized: set NOTARY_PROFILE to a notarytool keychain profile" >&2
fi
cp "$dmg" "$out/LectureStudio.dmg"   # unversioned copy for a stable "latest" download URL
shasum -a 256 "$dmg"
echo "built: $dmg"
