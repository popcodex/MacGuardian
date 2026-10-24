#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swift-cache"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$SWIFTPM_MODULECACHE_OVERRIDE" dist Resources
swift build --build-system native --scratch-path .build-native --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security -c release --arch arm64
swift Scripts/Artwork.swift "$PWD/Resources"
python3 Scripts/make-icon.py
ARCHIVE="$PWD/dist/MacGuardian-app.zip"
TEMP_ROOT=$(mktemp -d /private/tmp/MacGuardian-build.XXXXXX)
trap 'rm -rf "$TEMP_ROOT"' EXIT
APP="$TEMP_ROOT/MacGuardian.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
BIN_DIR=$(swift build --build-system native --scratch-path .build-native --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security -c release --arch arm64 --show-bin-path)
cp "$BIN_DIR/MacGuardian" "$APP/Contents/MacOS/MacGuardian"
cp Resources/MacGuardian.icns "$APP/Contents/Resources/"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
xattr -cr "$APP"
codesign --force --options runtime --sign "${MACGUARDIAN_SIGN_IDENTITY:--}" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
file "$APP/Contents/MacOS/MacGuardian"
ditto -c -k --norsrc --noextattr --keepParent "$APP" "$ARCHIVE"
echo "Compilación firmada archivada: $ARCHIVE"
