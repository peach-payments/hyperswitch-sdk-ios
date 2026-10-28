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

# Pod names are peach-prefixed to avoid colliding with juspay's identically-named pods on the
# public CocoaPods CDN (theirs are at higher versions and would otherwise win resolution). The
# Release zip + GitHub repo keep the hyperswitch-sdk-ios name — that's the repo, not the pod.
PODSPECS=(
    "peachpayments-hyperswitch-ios.podspec"
    "peachpayments-hyperswitch-ios-lite.podspec"
    "peachpayments-hyperswitch-ios-authentication.podspec"
)
MAIN_PODSPEC="peachpayments-hyperswitch-ios.podspec"
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
lockstep_version "peachpayments-hyperswitch-ios-lite.podspec"
lockstep_version "peachpayments-hyperswitch-ios-authentication.podspec"

VERSION_SWIFT="hyperswitchSDK/Shared/Version.swift"
if [ -f "$VERSION_SWIFT" ]; then
    echo "    setting ${VERSION_SWIFT} SDKVersion.current = ${VERSION}"
    sed -i.bak -E "s/(static let current[[:space:]]*=[[:space:]]*\")[^\"]*(\")/\1${VERSION}\2/" "$VERSION_SWIFT"
    rm -f "${VERSION_SWIFT}.bak"
fi

# ----- 2. build the JS bundle ------------------------------------------------------------------
echo "==> Building JS bundle (yarn bundle:ios)"
( cd "$REPO_ROOT" && yarn bundle:ios )

# ----- 3. (optional) rebuild reproducible xcframeworks (Core) ---------------------------------
# These change on a React Native bump -- and also whenever anything in patches/
# changes, since the Core frameworks are built from node_modules. The rebuild needs xcodegen +
# pod install to materialise frameworkgen/DummyApp.xcworkspace first. So the rebuild is OPT-IN:
# by default we ship the xcframeworks already on disk. Set REBUILD_XCFRAMEWORKS=1 to regenerate.
if [ "${REBUILD_XCFRAMEWORKS:-0}" = "1" ]; then
    echo "==> Rebuilding xcframeworks (frameworkgen)"
    require xcodegen
    (
        cd "$SCRIPT_DIR/frameworkgen"
        xcodegen generate                 # project.yml -> DummyApp.xcodeproj
        # USE_FRAMEWORKS is what makes the Podfile call use_frameworks!. Without it every
        # pod builds as a static library into Products/usr/local/lib, the archive contains
        # no Products/Library/Frameworks, and archive.sh has nothing to tar. The whole
        # point of frameworkgen is producing dynamic frameworks, so it is not optional.
        USE_FRAMEWORKS=dynamic bundle exec pod install   # -> DummyApp.xcworkspace
        ./scripts/archive.sh iphoneos
        ./scripts/archive.sh iphonesimulator
        ./scripts/framework.sh
    )
else
    echo "==> Using on-disk xcframeworks (set REBUILD_XCFRAMEWORKS=1 to regenerate)"
    # Only Core is vendored as xcframeworks. The paypal subspec pulls the
    # public PayPal pods and compiles frameworkgen/paypal/Source, so there is no
    # frameworkgen/Frameworks/PayPal to check for -- the published pod has never had one.
    for d in Core; do
        count=$(ls -d "frameworkgen/Frameworks/$d"/*.xcframework 2>/dev/null | wc -l | tr -d ' ')
        [ "$count" -gt 0 ] || { echo "ERROR: no xcframeworks in frameworkgen/Frameworks/$d — run with REBUILD_XCFRAMEWORKS=1."; exit 1; }
        echo "    frameworkgen/Frameworks/$d: $count xcframework(s)"
    done
fi

# ----- 3b. the core subspec must be self-contained ---------------------------------------------
# Core is what peachpayments_flutter and every plain `pod '.../core'` integration gets. A
# framework vendored here that links something shipped only by another subspec passes every
# build and then kills the app at launch with
# `dyld: Library not loaded: @rpath/<X>.framework/<X>`.
#
# That shipped in 0.8.0 through 0.8.2: framework.sh meant to keep the netcetera 3DS module out of
# Core, but its exclusion list had stray commas and hyphens where the framework name has
# underscores, so the module -- which links ThreeDS_SDK -- was vendored by core while ThreeDS_SDK
# itself ships only in netcetera3ds. Three releases went out before a merchant reported it.
echo "==> Checking core's vendored frameworks are self-contained"
subspec_only_frameworks="ThreeDS_SDK HyperswitchScanCard"
dangling=""
for xc in frameworkgen/Frameworks/Core/*.xcframework; do
    name=$(basename "$xc" .xcframework)
    binary=$(find "$xc" -type f -name "$name" | head -1)
    [ -n "$binary" ] || continue
    for dep in $subspec_only_frameworks; do
        if otool -L "$binary" 2>/dev/null | grep -q "/${dep}.framework/${dep}"; then
            dangling="${dangling}\n    $name links $dep, which ships only in another subspec"
        fi
    done
done
if [ -n "$dangling" ]; then
    printf "ERROR: core would ship a dangling link and crash at launch:%b\n" "$dangling"
    echo "    Fix frameworkgen/scripts/framework.sh so the framework lands in its own subspec."
    exit 1
fi
echo "    core is self-contained"

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
copy_into "frameworkgen/Frameworks/ReactNative"
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
# NOTE: run this script under Xcode 26.x (DEVELOPER_DIR=/Applications/Xcode-26.3.0.app/
# Contents/Developer). Xcode 27 rejects IPHONEOS_DEPLOYMENT_TARGET below 15.0, and two
# subspecs pull dependencies that still declare lower: airborne -> HyperOTA/HyperCore at
# 12.0, paypal -> PayPal at 14.0. A podspec cannot raise a DEPENDENCY's deployment target,
# HyperOTA 0.0.8 is the newest published, and our frameworkgen Podfile's post_install does
# not apply here because lint resolves those pods fresh.
#
# Measured under Xcode 27: core, common, scancard and netcetera3ds all pass -- only
# airborne and paypal fail. Neither is in default_subspec, nothing references paypal, and
# airborne is pinned only by peachpayments_flutter_airborne, which is publish_to: none. So
# this blocks releases on this machine, not merchants. The lint is deliberately NOT narrowed
# to dodge it: that would hide a real defect in two published subspecs.
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

# ----- 7b. Swift Package Manager assets ---------------------------------------------------------
# One zip + checksum per xcframework, and Package.swift rewritten from path: to url:/checksum:.
# SPM reads Package.swift from the TAG, so the rewrite has to be committed before the tag moves.
# Non-fatal on purpose. spm-release.sh rewrites Package.swift from path: to url:, and that
# rewrite is committed -- so on the next release there are no path: entries left and the
# script exits non-zero. It used to abort the whole run here, leaving a GitHub Release
# published but the podspecs unpushed: a half-released version nobody could resolve. The
# pods are the product; SPM is additional, so a failure here must not block step 8.
if [ "${SKIP_SPM:-0}" != "1" ]; then
    echo "==> Building SPM artifacts"
    if "${SCRIPT_DIR}/frameworkgen/scripts/spm-release.sh" "$VERSION" "$FORK_SLUG" "$TAG"; then
        for zip_file in "${SCRIPT_DIR}"/spm-artifacts/*.xcframework.zip; do
            gh release upload "$TAG" "$zip_file" --repo "$FORK_SLUG" --clobber
        done
        echo "    SPM binary targets uploaded to ${TAG}"
    else
        echo "    WARNING: SPM artifacts skipped (spm-release.sh failed)."
        echo "    Package.swift still points at the previous release, so Swift Package Manager"
        echo "    consumers stay on it. CocoaPods is unaffected. Re-run spm-release.sh against a"
        echo "    path-based Package.swift to restore SPM for ${VERSION}."
    fi
fi

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
cat <<EOF

================================================================================
NOT DONE YET -- Swift Package Manager still points at the previous release.

spm-release.sh rewrote Package.swift in the working tree, but \`gh release create\`
tagged ${TAG} at the remote's HEAD, which is the commit BEFORE that rewrite. SPM
reads Package.swift from the TAG, so until the rewrite is committed and the tag
moved, anyone depending on ${VERSION} resolves the previous version's URLs.
CocoaPods is unaffected -- it fetches the release asset, which is already correct.

Run:

  git add Package.swift hyperswitchSDK/Shared/Version.swift *.podspec
  git commit -m "chore: record the ${VERSION} release artefacts"
  git fetch origin && git merge --ff-only origin/main   # pick up the pod repo push commits
  git tag -f ${TAG} HEAD
  git push origin main && git push origin -f ${TAG}

Then confirm a consumer resolves it:

  swift package resolve   # in a scratch package depending on ${VERSION}
================================================================================

EOF
echo "Publish complete — pods ${VERSION} live via ${FORK_SLUG} (Release ${TAG} + spec repo ${SPEC_REPO_NAME})."
