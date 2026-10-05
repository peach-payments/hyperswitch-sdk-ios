#!/usr/bin/env bash

SRCROOT=$(pwd)
export SRCROOT

PLATFORM=$1

OUT="$PLATFORM-binary.tar.gz"
set -euo pipefail

echo $(pwd)

function archive() {
  SDK=$PLATFORM
  DESTINATION=""

  architectures="\"arm64 x86_64\""
  if [ "$PLATFORM" == "iphoneos" ]; then
    architectures="arm64"
  fi

  # Note the $(inherited) in OTHER_SWIFT_FLAGS below. A build setting passed on the
  # xcodebuild command line sits at the highest precedence level and REPLACES each
  # target's own value rather than adding to it. Without $(inherited), pods lose the
  # flags their xcconfig sets -- Sentry loses -import-underlying-module, so its Swift
  # half can no longer see the Obj-C module and fails with "cannot find type 'NSObject'
  # in scope" across ~40 files.
  #
  # It is escaped as \$(inherited) because XCODEBUILD_COMMAND is a double-quoted string
  # that is later eval'd: unescaped, bash would run "inherited" as a command at assignment
  # time. The single quotes protect it during eval's own parse.
  XCODEBUILD_COMMAND="xcodebuild archive \
    -workspace "DummyApp.xcworkspace" \
    -scheme DummyApp \
    -configuration Release \
    -archivePath $SRCROOT/DummyApp-$PLATFORM.xcarchive \
    -sdk $SDK \
    $DESTINATION \
    ENABLE_BITCODE=NO \
    SKIP_INSTALL=NO \
    ARCHS=$architectures \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    OTHER_SWIFT_FLAGS='\$(inherited) -Xfrontend -empty-abi-descriptor' \
    SUPPORTS_MACCATALYST=NO | xcbeautify"

  eval $XCODEBUILD_COMMAND
}

archive

OUT=$(pwd)/$OUT
pushd "$SRCROOT/DummyApp-$PLATFORM.xcarchive/Products/Library/Frameworks" || exit 1
tar -cvf "$OUT" ./*
popd || exit 1
