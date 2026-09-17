#!/usr/bin/env bash

SRCROOT=$(pwd)
export SRCROOT

set -euo pipefail

excluded_frameworks=("Pods_DummyApp" "DummyApp", "react-native-hyperswitch-netcetera-3ds", "react_native_hyperswitch_scancard")
sentry_frameworks=("Sentry" "SentryPrivate" "RNSentry")
paypal_frameworks=("PayPal" "ReactNativeHyperswitchPaypal")

function unzip_archives() {
  PLATFORM="$1"

  mkdir -p ./build/"$PLATFORM"

  tar zxvf "./$PLATFORM-binary.tar.gz" --directory ./build/"$PLATFORM"
}

function create_xcframework() {
  rm -rf $SRCROOT/Frameworks
  mkdir $SRCROOT/Frameworks

  # Find frameworks
  for framework in $(find ./build/iphoneos/ -type d -name "*.framework"); do
    basename=$(basename $framework)
    framework_name=$(basename $framework .framework)

    echo "Processing $framework_name"

    if [[ " ${excluded_frameworks[*]} " =~ " ${framework_name} " ]]; then
      continue
    fi

    if [[ " ${sentry_frameworks[*]} " =~ " ${framework_name} " ]]; then
      xcodebuild -create-xcframework \
      -framework ./build/iphonesimulator/$basename \
      -framework ./build/iphoneos/$basename \
      -output $SRCROOT/Frameworks/Sentry/$framework_name.xcframework

    elif [[ " ${paypal_frameworks[*]} " =~ " ${framework_name} " ]]; then
      xcodebuild -create-xcframework \
      -framework ./build/iphonesimulator/$basename \
      -framework ./build/iphoneos/$basename \
      -output $SRCROOT/Frameworks/PayPal/$framework_name.xcframework
      
    else
      xcodebuild -create-xcframework \
        -framework ./build/iphonesimulator/$basename \
        -framework ./build/iphoneos/$basename \
        -output $SRCROOT/Frameworks/Core/$framework_name.xcframework
    fi

    echo "Created xcframework: $framework_name.xcframework"
  done

  copy_prebuilt_react_native

  cp LICENSE Frameworks/
  # tar -cvzf HyperswitchSDK.tar.gz Frameworks
}

# React Native 0.87 no longer compiles its core into the consuming app; it ships prebuilt
# binaries instead (React-Core-prebuilt, ReactNativeDependencies, hermes-engine). They are
# therefore absent from the DummyApp archive, so the loop above cannot find them -- before
# 0.87 the same content arrived as ~55 individually built frameworks.
#
# This pod exists so that NON-React-Native hosts (the Flutter plugin, merchant native apps)
# can consume the SDK without a node_modules, so those binaries have to be vendored here or
# the published pod contains no React Native at all.
#
# Binaries alone are not enough. React.xcframework carries the <React/...> headers and the
# framework module map, but building that module also needs the <react/...>, <yoga/...>
# headers (flattened by React-Core-prebuilt's prepare_command into its Headers/) and the
# folly/glog/boost namespaces (ReactNativeDependencies' Headers/). Both trees are copied
# alongside and exposed by the `reactnative` subspec.
function copy_prebuilt_react_native() {
  local pods="$SRCROOT/Pods"
  # The xcframeworks go into Frameworks/Core, the same subspec as the SDK's own sources:
  # `import React` only resolves when the framework is vendored by the subspec being
  # compiled. Only the header trees live under Frameworks/ReactNative, so that the
  # header_mappings_dir needed to preserve <react/...> nesting does not disturb core.
  local binaries_dest="$SRCROOT/Frameworks/Core"
  local dest="$SRCROOT/Frameworks/ReactNative"
  mkdir -p "$dest/Headers" "$binaries_dest"

  local prebuilt=(
    "$pods/React-Core-prebuilt/React.xcframework"
    "$pods/ReactNativeDependencies/framework/packages/react-native/ReactNativeDependencies.xcframework"
    "$pods/hermes-engine/destroot/Library/Frameworks/universal/hermesvm.xcframework"
  )
  local header_trees=(
    "$pods/React-Core-prebuilt/Headers"
    "$pods/ReactNativeDependencies/Headers"
  )

  for source in "${prebuilt[@]}"; do
    if [ ! -d "$source" ]; then
      echo "ERROR: expected prebuilt xcframework missing: $source" >&2
      echo "       Run pod install in frameworkgen first (USE_FRAMEWORKS=dynamic)." >&2
      exit 1
    fi
    echo "Vendoring prebuilt $(basename "$source")"
    rsync -a --exclude '.DS_Store' "$source" "$binaries_dest/"
  done

  for tree in "${header_trees[@]}"; do
    if [ ! -d "$tree" ]; then
      echo "ERROR: expected prebuilt header tree missing: $tree" >&2
      exit 1
    fi
    # module.modulemap is deliberately excluded. React-Core-prebuilt ships one declaring
    # CoreModules, yoga, RCTImage and friends; upstream can carry it because that pod owns
    # its own module scope. Here the tree is only a header search path, and a loose module
    # map on such a path poisons clang's module graph -- system modules (os, Security,
    # CoreData, ...) stop resolving. The headers alone are what this pod needs.
    echo "Vendoring headers from $(basename "$(dirname "$tree")")"
    rsync -a --exclude '.DS_Store' --exclude 'module.modulemap' "$tree/" "$dest/Headers/"
  done
}

cd $SRCROOT
unzip_archives iphoneos
unzip_archives iphonesimulator
create_xcframework
