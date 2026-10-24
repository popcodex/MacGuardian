#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swift-cache"
DEVELOPER_DIR_PATH=$(xcode-select -p)
SWIFTC_PATH=$(xcrun --find swiftc)
TOOLCHAIN_USR=$(dirname "$(dirname "$SWIFTC_PATH")")
ARGS=(--build-system native --scratch-path .build-native --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security --disable-xctest)

# Command Line Tools and full Xcode locate Swift Testing differently.
for FRAMEWORKS in "$DEVELOPER_DIR_PATH/Library/Developer/Frameworks" "$DEVELOPER_DIR_PATH/Platforms/MacOSX.platform/Developer/Library/Frameworks"; do
    if [[ -d "$FRAMEWORKS/Testing.framework" ]]; then
        ARGS+=(-Xswiftc -F -Xswiftc "$FRAMEWORKS" -Xlinker -rpath -Xlinker "$FRAMEWORKS")
        break
    fi
done
PLUGIN="$TOOLCHAIN_USR/lib/swift/host/plugins/testing/libTestingMacros.dylib"
if [[ -f "$PLUGIN" ]]; then
    ARGS+=(-Xswiftc -load-plugin-library -Xswiftc "$PLUGIN")
fi
swift test "${ARGS[@]}"
