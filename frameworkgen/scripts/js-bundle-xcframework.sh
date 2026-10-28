#!/usr/bin/env bash
# Package hyperswitch.bundle as an xcframework, for Swift Package Manager only.
#
# CocoaPods ships the JS bundle through `core.resources`, straight out of the pod archive.
# Swift Package Manager cannot: it takes package SOURCE from the git tag, and the bundle is a
# build artifact that is not committed. The result was a package that resolved, downloaded all
# its binary targets, compiled -- and then had no JavaScript to run, so the payment sheet never
# started. Silent, because a missing bundle URL is indistinguishable from a slow start.
#
# Committing a 2.8 MB minified bundle on every release would grow the repo permanently, so it
# travels the same way the other binary targets do: as a zip on the GitHub release, referenced
# by url + checksum from Package.swift. That costs the repo nothing and reuses machinery that
# already works.
#
# The framework carries a stub binary because an xcframework slice has to have one. Nothing
# calls into it; it exists so the bundle has somewhere to live that Xcode will embed. The
# lookup side is RNViewManager.bundleURL(), which reaches for
# Frameworks/HyperswitchJS.framework/hyperswitch.bundle under SWIFT_PACKAGE.
#
# This deliberately does NOT go into Frameworks/Core: the core subspec vendors
# Core/*.xcframework, and CocoaPods would then embed a second copy of a bundle it already
# ships as a resource.
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd )"   # the ios/ dir
BUNDLE="${SCRIPT_DIR}/hyperswitchSDK/Core/Resources/hyperswitch.bundle"
OUT_DIR="${SCRIPT_DIR}/frameworkgen/Frameworks/ReactNative"
XCF="${OUT_DIR}/HyperswitchJS.xcframework"
NAME="HyperswitchJS"
MIN_IOS="15.0"

[ -f "$BUNDLE" ] || { echo "ERROR: $BUNDLE missing -- run 'yarn bundle:ios' first." >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# One trivial symbol, so the slice is a real Mach-O rather than an empty file.
cat > "$WORK/stub.c" <<'EOF'
/* Placeholder so the framework slice is a valid Mach-O. Nothing calls this. */
__attribute__((visibility("default"))) const char *HyperswitchJSBundleMarker(void) {
    return "hyperswitch.bundle";
}
EOF

build_slice() {   # $1 = slice dir name   $2... = clang -target triples
    local slice="$1"; shift
    local fw="$WORK/$slice/${NAME}.framework"
    mkdir -p "$fw"

    # One dylib per arch, then lipo. -isysroot comes from the matching SDK.
    local dylibs=()
    local i=0
    for triple in "$@"; do
        local sdk="iphoneos"
        case "$triple" in *simulator) sdk="iphonesimulator";; esac
        local sysroot; sysroot="$(xcrun --sdk "$sdk" --show-sdk-path)"
        clang -dynamiclib "$WORK/stub.c" \
            -target "$triple" -isysroot "$sysroot" \
            -install_name "@rpath/${NAME}.framework/${NAME}" \
            -o "$WORK/$slice/${NAME}-$i.dylib"
        dylibs+=("$WORK/$slice/${NAME}-$i.dylib")
        i=$((i+1))
    done
    lipo -create "${dylibs[@]}" -output "$fw/${NAME}"

    cp -R "$BUNDLE" "$fw/"

    local platform="iPhoneOS"
    case "$1" in *simulator) platform="iPhoneSimulator";; esac
    cat > "$fw/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>${NAME}</string>
  <key>CFBundleIdentifier</key><string>io.peachpayments.${NAME}</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>${NAME}</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>MinimumOSVersion</key><string>${MIN_IOS}</string>
  <key>CFBundleSupportedPlatforms</key><array><string>${platform}</string></array>
</dict>
</plist>
EOF
    echo "$fw"
}

echo "==> Packaging hyperswitch.bundle as ${NAME}.xcframework"
DEVICE_FW="$(build_slice device "arm64-apple-ios${MIN_IOS}")"
SIM_FW="$(build_slice simulator "arm64-apple-ios${MIN_IOS}-simulator" "x86_64-apple-ios${MIN_IOS}-simulator")"

mkdir -p "$OUT_DIR"
rm -rf "$XCF"
xcodebuild -create-xcframework \
    -framework "$DEVICE_FW" \
    -framework "$SIM_FW" \
    -output "$XCF" > /dev/null

echo "    $XCF"
find "$XCF" -name "hyperswitch.bundle" | sed 's|^|    carries |'
