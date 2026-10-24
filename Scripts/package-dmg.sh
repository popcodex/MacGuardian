#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ -f dist/MacGuardian-app.zip ]] || Scripts/build.sh
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Versión no válida" >&2; exit 1; }
OUTPUT_DIR="${MACGUARDIAN_OUTPUT_DIR:-$PWD/dist/v$VERSION}"
mkdir -p "$OUTPUT_DIR"
if [[ ! "$PWD/dist/MacGuardian-app.zip" -ef "$OUTPUT_DIR/MacGuardian-app.zip" ]]; then cp dist/MacGuardian-app.zip "$OUTPUT_DIR/MacGuardian-app.zip"; fi
STAGE=$(mktemp -d /private/tmp/MacGuardian-stage.XXXXXX)
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/.background"
ditto -x -k dist/MacGuardian-app.zip "$STAGE"
[[ -L "$STAGE/Aplicaciones" ]] || ln -s /Applications "$STAGE/Aplicaciones"
cp Resources/InstallerBackground.png "$STAGE/.background/background.png"
cp Resources/MacGuardian.icns "$STAGE/.VolumeIcon.icns"
cp Docs/INSTALACION.txt "$STAGE/LEEME.txt"
xattr -cr "$STAGE/MacGuardian.app"
hdiutil create -ov -volname MacGuardian -srcfolder "$STAGE" -format UDRW "$OUTPUT_DIR/MacGuardian-layout.dmg"
MOUNT=$(mktemp -d /private/tmp/MacGuardian-volume.XXXXXX)
hdiutil attach "$OUTPUT_DIR/MacGuardian-layout.dmg" -mountpoint "$MOUNT" -nobrowse
trap 'hdiutil detach "$MOUNT" >/dev/null 2>&1 || true; rmdir "$MOUNT" >/dev/null 2>&1 || true; rm -rf "$STAGE"' EXIT
xattr -cr "$MOUNT"
# Set the custom volume icon using the FinderInfo flag kHasCustomIcon.
xattr -wx com.apple.FinderInfo 0000000000000000040000000000000000000000000000000000000000000000 "$MOUNT"
python3 Scripts/dmg-layout.py "$MOUNT"
xattr -cr "$MOUNT/MacGuardian.app"
codesign --verify --deep --strict --verbose=2 "$MOUNT/MacGuardian.app"
sync
hdiutil detach "$MOUNT"
rmdir "$MOUNT"
rm -rf "$STAGE"
trap - EXIT
hdiutil convert "$OUTPUT_DIR/MacGuardian-layout.dmg" -ov -format UDZO -imagekey zlib-level=9 -o "$OUTPUT_DIR/MacGuardian.dmg"
hdiutil verify "$OUTPUT_DIR/MacGuardian.dmg"
(cd "$OUTPUT_DIR" && shasum -a 256 MacGuardian.dmg MacGuardian-app.zip > SHA256SUMS.txt)
echo "Instalador: $OUTPUT_DIR/MacGuardian.dmg"
