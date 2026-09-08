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

dmg="$out/LectureStudio-$version.dmg"
hdiutil create -quiet -volname "Lecture Studio" -srcfolder "$app" -ov -format UDZO "$dmg"
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
