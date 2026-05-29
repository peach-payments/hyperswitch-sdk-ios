#!/bin/bash

# Builds and publishes the Peach iOS SDK as CocoaPods pods.
#
# GitLab's package registry has NO CocoaPods publish API (it is pull-only), so distribution is:
#   1. a prebuilt binary zip attached to a GitHub Release on the fork, and
#   2. the podspecs pushed into the fork's CocoaPods spec-repo layout (`pod repo push`).
# The pod's `s.source` is an :http URL pointing at that Release zip.
#
# This script is the release engineer's one command. Run it from a mac with the iOS toolchain,
# authenticated to GitHub via `gh auth login`.
#
# Ordering rule (do not reorder): build zip -> local file:// lint -> create Release with zip
# -> remote spec lint -> pod repo push. Never push a podspec whose :http asset is not yet live.
# Any content change REQUIRES a version bump (CocoaPods caches by version + checksum).

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"   # the ios/ dir
REPO_ROOT="${SCRIPT_DIR}/.."

# ----- configuration ---------------------------------------------------------------------------
FORK_SLUG="peach-payments/hyperswitch-sdk-ios"   # GitHub repo: source-of-truth + spec source + releases
SPEC_REPO_NAME="peach-hyperswitch"               # local `pod repo` name for the spec source
SPEC_REPO_URL="https://github.com/${FORK_SLUG}.git"

# The two vendored xcframeworks that NO build script regenerates. They are preserved as assets on a
# one-time GitHub Release (see Stage 0). Set this tag once that release exists, then this script
# pulls them when assembling the zip.
VENDOR_FRAMEWORKS_TAG="${VENDOR_FRAMEWORKS_TAG:-vendor-frameworks}"

PODSPECS=(
    "hyperswitch-sdk-ios.podspec"
    "hyperswitch-sdk-ios-lite.podspec"
    "hyperswitch-sdk-ios-authentication.podspec"
)
MAIN_PODSPEC="hyperswitch-sdk-ios.podspec"
POD="bundle exec pod"

# ----- helpers ---------------------------------------------------------------------------------
read_podspec_version() {   # $1 = podspec path
    grep -m1 -E '^version[[:space:]]*=' "$1" | sed -E 's/.*"([^"]+)".*/\1/'
}

require() {                 # $1 = command name
    command -v "$1" >/dev/null 2>&1 || { echo "ERROR: '$1' is required but not installed."; exit 1; }
}

require gh
require zip
require curl
gh auth status >/dev/null 2>&1 || { echo "ERROR: not authenticated to GitHub. Run 'gh auth login'."; exit 1; }

cd "$SCRIPT_DIR"

# ----- 1. version lockstep ---------------------------------------------------------------------
# The main podspec's version is authoritative. lite + authentication + Version.swift are rewritten
# to match so all three pods share ONE zip / tag / URL (single download, single cached source).
VERSION=$(read_podspec_version "$MAIN_PODSPEC")
[ -n "$VERSION" ] || { echo "ERROR: could not read version from $MAIN_PODSPEC"; exit 1; }
TAG="v${VERSION}"
ZIP="hyperswitch-sdk-ios-${VERSION}.zip"
ASSET_URL="https://github.com/${FORK_SLUG}/releases/download/${TAG}/${ZIP}"

echo "==> Release version ${VERSION} (tag ${TAG}, asset ${ZIP})"

lockstep_version() {        # $1 = podspec path
    local current; current=$(read_podspec_version "$1")
    if [ "$current" != "$VERSION" ]; then
        echo "    lockstepping $1: ${current} -> ${VERSION}"
        # the version literal is always on line 1 of each podspec; rewrite just that line
        sed -i.bak -E "1s/^version[[:space:]]*=.*/version = \"${VERSION}\"/" "$1"
        rm -f "${1}.bak"
    fi
}
lockstep_version "hyperswitch-sdk-ios-lite.podspec"
lockstep_version "hyperswitch-sdk-ios-authentication.podspec"

VERSION_SWIFT="hyperswitchSDK/Shared/Version.swift"
if [ -f "$VERSION_SWIFT" ]; then
    echo "    setting ${VERSION_SWIFT} SDKVersion.current = ${VERSION}"
    sed -i.bak -E "s/(static let current[[:space:]]*=[[:space:]]*\")[^\"]*(\")/\1${VERSION}\2/" "$VERSION_SWIFT"
    rm -f "${VERSION_SWIFT}.bak"
fi

# ----- 2. build the JS bundle ------------------------------------------------------------------
echo "==> Building JS bundle (yarn bundle:ios)"
( cd "$REPO_ROOT" && yarn bundle:ios )

# ----- 3. (optional) rebuild reproducible xcframeworks (Core/Sentry/PayPal) --------------------
# These only change on a React Native / Sentry / PayPal bump, and the rebuild needs xcodegen +
# pod install to materialise frameworkgen/DummyApp.xcworkspace first. So the rebuild is OPT-IN:
# by default we ship the xcframeworks already on disk. Set REBUILD_XCFRAMEWORKS=1 to regenerate.
if [ "${REBUILD_XCFRAMEWORKS:-0}" = "1" ]; then
    echo "==> Rebuilding xcframeworks (frameworkgen)"
    require xcodegen
    (
        cd "$SCRIPT_DIR/frameworkgen"
        xcodegen generate                 # project.yml -> DummyApp.xcodeproj
        bundle exec pod install           # -> DummyApp.xcworkspace (archive.sh needs this)
        ./scripts/archive.sh iphoneos
        ./scripts/archive.sh iphonesimulator
        ./scripts/framework.sh
    )
else
    echo "==> Using on-disk xcframeworks (set REBUILD_XCFRAMEWORKS=1 to regenerate)"
    for d in Core Sentry PayPal; do
        count=$(ls -d "frameworkgen/Frameworks/$d"/*.xcframework 2>/dev/null | wc -l | tr -d ' ')
        [ "$count" -gt 0 ] || { echo "ERROR: no xcframeworks in frameworkgen/Frameworks/$d — run with REBUILD_XCFRAMEWORKS=1."; exit 1; }
        echo "    frameworkgen/Frameworks/$d: $count xcframework(s)"
    done
fi

# ----- 4. fetch the non-reproducible vendored xcframeworks ------------------------------------
# ThreeDS_SDK + HyperswitchScanCard are vendored binaries; pull them from the vendor-frameworks
# release if they are not already present on disk.
ensure_vendored() {        # $1 = relative path to .xcframework  $2 = asset name in vendor release
    local path="$1" asset="$2"
    if [ -d "$path" ]; then
        echo "    present: $path"
        return
    fi
    echo "    fetching $asset from release ${VENDOR_FRAMEWORKS_TAG}"
    local dest_dir; dest_dir=$(dirname "$path")
    mkdir -p "$dest_dir"
    gh release download "$VENDOR_FRAMEWORKS_TAG" --repo "$FORK_SLUG" --pattern "$asset" --dir "$dest_dir" --clobber
    ( cd "$dest_dir" && unzip -oq "$asset" && rm -f "$asset" )
}
echo "==> Ensuring vendored xcframeworks present"
ensure_vendored "frameworkgen/3ds/Frameworks/ThreeDS_SDK.xcframework" "ThreeDS_SDK.xcframework.zip"
ensure_vendored "frameworkgen/scanCard/Frameworks/HyperswitchScanCard.xcframework" "HyperswitchScanCard.xcframework.zip"

# ----- 5. assemble the distribution zip --------------------------------------------------------
# The zip root mirrors ios/ so every source_files / vendored_frameworks / resources glob in the
# podspecs resolves unchanged. Only the subtrees the podspecs reference are included.
echo "==> Assembling ${ZIP}"
STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT

copy_into() {              # $1 = source path relative to ios/   (preserves the relative path under STAGING)
    local rel="$1"
    if [ ! -e "$rel" ]; then
        echo "ERROR: expected '$rel' to exist for the zip but it does not."
        exit 1
    fi
    mkdir -p "$STAGING/$(dirname "$rel")"
    # -R recurse, exclude junk
    rsync -a --exclude '.DS_Store' --exclude 'xcuserdata' "$rel" "$STAGING/$(dirname "$rel")/"
}

copy_into "LICENSE"
copy_into "hyperswitchSDK/Core"
copy_into "hyperswitchSDK/CoreLite"
copy_into "hyperswitchSDK/Shared"
copy_into "hyperswitchSDK/AuthenticationModule"
copy_into "frameworkgen/Frameworks/Core"
copy_into "frameworkgen/Frameworks/Sentry"
copy_into "frameworkgen/Frameworks/PayPal"
copy_into "frameworkgen/scanCard/Source"
copy_into "frameworkgen/scanCard/Frameworks"
copy_into "frameworkgen/3ds/Source"
copy_into "frameworkgen/3ds/Frameworks"
copy_into "frameworkgen/paypal/Source"

ZIP_ABS="${SCRIPT_DIR}/${ZIP}"
rm -f "$ZIP_ABS"
( cd "$STAGING" && zip -rqy "$ZIP_ABS" . )
echo "    wrote $ZIP_ABS ($(du -h "$ZIP_ABS" | cut -f1))"

# ----- 6. pre-upload local lint (file:// against the just-built zip) ---------------------------
# Point each s.source at the local zip so lint can actually unzip + resolve every glob before the
# remote asset exists. Restore the real :http URL afterward via git checkout of the podspec line.
echo "==> Local lint (file://${ZIP})"
FILE_URL="file://${ZIP_ABS}"
for podspec in "${PODSPECS[@]}"; do
    cp "$podspec" "${podspec}.orig"
    sed -i.bak -E "s#\{ :http => \"[^\"]*\" \}#{ :http => \"${FILE_URL}\" }#" "$podspec"
    rm -f "${podspec}.bak"
done
lint_status=0
for podspec in "${PODSPECS[@]}"; do
    echo "--- pod lib lint $podspec"
    if ! $POD lib lint "$podspec" --allow-warnings --skip-import-validation; then
        lint_status=1
    fi
done
# restore real :http URLs
for podspec in "${PODSPECS[@]}"; do
    mv "${podspec}.orig" "$podspec"
done
[ "$lint_status" -eq 0 ] || { echo "ERROR: local lint failed; not publishing."; exit 1; }

# ----- 7. create / update the GitHub Release and upload the zip --------------------------------
echo "==> Publishing GitHub Release ${TAG} on ${FORK_SLUG}"
if gh release view "$TAG" --repo "$FORK_SLUG" >/dev/null 2>&1; then
    gh release upload "$TAG" "$ZIP_ABS" --repo "$FORK_SLUG" --clobber
else
    gh release create "$TAG" "$ZIP_ABS" --repo "$FORK_SLUG" \
        --title "$TAG" --notes "Peach Hyperswitch iOS SDK ${VERSION}"
fi
echo "    asset live at ${ASSET_URL}"

# ----- 8. remote gate + publish podspecs -------------------------------------------------------
# Register the spec repo locally if needed.
if ! $POD repo list 2>/dev/null | grep -q "^${SPEC_REPO_NAME}$"; then
    echo "==> Adding spec repo ${SPEC_REPO_NAME} -> ${SPEC_REPO_URL}"
    $POD repo add "$SPEC_REPO_NAME" "$SPEC_REPO_URL"
fi

echo "==> Pushing podspecs to spec repo ${SPEC_REPO_NAME}"
for podspec in "${PODSPECS[@]}"; do
    echo "--- pod repo push $podspec"
    $POD repo push "$SPEC_REPO_NAME" "$podspec" \
        --allow-warnings --skip-import-validation \
        --sources="${SPEC_REPO_URL},https://cdn.cocoapods.org/"
done

rm -f "$ZIP_ABS"
echo "Publish complete — pods ${VERSION} live via ${FORK_SLUG} (Release ${TAG} + spec repo ${SPEC_REPO_NAME})."
