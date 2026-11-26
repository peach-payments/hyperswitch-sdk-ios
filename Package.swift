// swift-tools-version:5.9
import PackageDescription

// Swift Package Manager distribution, alongside CocoaPods.
//
// Each binaryTarget points at a per-xcframework zip on the GitHub release for its tag, with a
// checksum. build-lib.sh emits those zips and rewrites the urls and checksums here as part of
// cutting a release, so a merchant can depend on this package by version without a checkout.
//
// React Native 0.87 ships its core prebuilt, so React.xcframework and friends are vendored
// rather than compiled. Building the React module needs the flattened <react/...>, <yoga/...>
// and folly/glog/boost headers on an include path -- the same requirement the podspec has.
// headerSearchPath may leave the target but not the package, which our layout satisfies.
//
// React Native 0.87 ships its core prebuilt, so React.xcframework and friends are vendored
// rather than compiled.
//
// Building the React module needs <react/...>, <yoga/...> and the folly/glog/boost headers
// reachable, and React.framework's own headers include several of them BY PATH. Against a
// loose header tree those includes are non-modular and raise
// -Werror=non-modular-include-in-framework-module. The podspec suppresses that with
// OTHER_CFLAGS; SPM's only equivalent is .unsafeFlags, which it forbids for packages consumed
// by version -- the way merchants add this one -- so that route was closed. Making the loose
// tree a module instead produced a React <-> headers cycle, since the tree's own headers
// include <React/...>.
//
// Upstream's prebuilt tarball already solves it: alongside React.xcframework it ships
// ReactNativeHeaders.xcframework, headers-only, carrying all 29 namespaces. Those headers are
// modular because they belong to a real binary artifact, which is exactly what both failed
// approaches lacked. CocoaPods cannot use it -- it refuses a vendored xcframework containing
// static libraries, and the stub .a is what makes it work for SPM -- so the two distributions
// take different artifacts from the same build: SPM the xcframework, CocoaPods the flattened
// header tree.
//
// The three Objective-C bridge shims live in a sibling target because SPM has no
// mixed-language targets. There is no compile-time coupling in either direction: they register
// Swift classes with the React Native bridge by name at runtime and none imports the generated
// -Swift.h.
//
// binaryTarget urls and checksums are rewritten per release by build-lib.sh.

let package = Package(
    name: "Hyperswitch",
    platforms: [.iOS(.v15)],
    // One product per CocoaPods subspec a merchant can ask for: core, netcetera3ds, scancard.
    //
    // Each optional product carries its own vendored binary, exactly as its subspec does, so core
    // never links a framework it does not ship. The Netcetera 3DS module links ThreeDS_SDK;
    // vendoring the module without ThreeDS_SDK is what crashed apps at launch in 0.8.0-0.8.2. Here
    // the bridge and ThreeDS_SDK are in the same product, so neither can be installed without the
    // other, and an app that adds only Hyperswitch gets neither.
    products: [
        .library(name: "Hyperswitch", targets: ["Hyperswitch", "HyperswitchObjC"]),
        .library(
            name: "HyperswitchNetcetera3DS",
            targets: ["HyperswitchNetcetera3dsBridge", "HyperswitchNetcetera3dsBridgeObjC", "ThreeDS_SDK"]
        ),
        .library(
            name: "HyperswitchScanCard",
            targets: ["HyperswitchScancardBridge", "HyperswitchScancardBridgeObjC", "HyperswitchScanCard"]
        ),
    ],
    targets: [
        // The JavaScript bundle the payment sheet runs, packaged as a framework so it can
        // travel as a binary artifact. CocoaPods ships it through `core.resources` out of the
        // pod archive; SPM takes package source from the git tag, where a build artifact like
        // this one is not committed, so without this the package resolved and compiled and
        // then had no JavaScript to run. Built by frameworkgen/scripts/js-bundle-xcframework.sh.
        .binaryTarget(
            name: "HyperswitchJS",
            url: "https://github.com/peach-payments/hyperswitch-sdk-ios/releases/download/v0.9.1/HyperswitchJS.xcframework.zip",
            checksum: "d4ac8848cf82108a2da1b3ef7d4fa4dc8dc2bbbff5f154c751739a4e6da0d5c8"
        ),
        .binaryTarget(
            name: "RNInAppBrowser",
            url: "https://github.com/peach-payments/hyperswitch-sdk-ios/releases/download/v0.9.1/RNInAppBrowser.xcframework.zip",
            checksum: "fd9bd065917ee81878d6f93c41feb0395ee2b9f4b0e167aa6b8c6d34fbe24bde"
        ),
        .binaryTarget(
            name: "RNSVG",
            url: "https://github.com/peach-payments/hyperswitch-sdk-ios/releases/download/v0.9.1/RNSVG.xcframework.zip",
            checksum: "a847e8c65265a87c8f645150910187799f3c5b9cc0405703b9ba8fc75d69e02d"
        ),
        .binaryTarget(
            name: "React",
            url: "https://github.com/peach-payments/hyperswitch-sdk-ios/releases/download/v0.9.1/React.xcframework.zip",
            checksum: "202ac4af1210f38255c9c294513e3438914a7aa24100c4f0afeba23ff2759b52"
        ),
        .binaryTarget(
            name: "ReactNativeHeaders",
            url: "https://github.com/peach-payments/hyperswitch-sdk-ios/releases/download/v0.9.1/ReactNativeHeaders.xcframework.zip",
            checksum: "2fb02abb28d3287976ee78ee8e6044967e9ea6596750953d5e7a847b5ada7d09"
        ),
        .binaryTarget(
            name: "ReactAppDependencyProvider",
            url: "https://github.com/peach-payments/hyperswitch-sdk-ios/releases/download/v0.9.1/ReactAppDependencyProvider.xcframework.zip",
            checksum: "2b8736e05998e8b5395a5823bf623450ec0dd9c4ccfe5668268d009004878ade"
        ),
        .binaryTarget(
            name: "ReactCodegen",
            url: "https://github.com/peach-payments/hyperswitch-sdk-ios/releases/download/v0.9.1/ReactCodegen.xcframework.zip",
            checksum: "a65164f74c950c27e037bcf83071c330b9798e090f8eeb0c89c7f5b9c7a1bc21"
        ),
        .binaryTarget(
            name: "ReactNativeDependencies",
            url: "https://github.com/peach-payments/hyperswitch-sdk-ios/releases/download/v0.9.1/ReactNativeDependencies.xcframework.zip",
            checksum: "aa356eaf0c8f03bd2f1ba36b64e80e5afa351c98b85bbed087f55d0a7c2103ba"
        ),
        .binaryTarget(
            name: "React_Codegen",
            url: "https://github.com/peach-payments/hyperswitch-sdk-ios/releases/download/v0.9.1/React_Codegen.xcframework.zip",
            checksum: "d648e69212e934e43c8bb2663bb82c5dea67bc507754331e3b1128f097d4ac5e"
        ),
        .binaryTarget(
            name: "hermesvm",
            url: "https://github.com/peach-payments/hyperswitch-sdk-ios/releases/download/v0.9.1/hermesvm.xcframework.zip",
            checksum: "4cf84c3922b88653dac92be1545b78015796a297d76d207bab1bb349e97d5132"
        ),
        // SPM has no mixed-language targets, and Core carries three Objective-C React Native
        // bridge shims among its Swift. They are split out here rather than moved on disk, so
        // the podspec globs and the Xcode project keep working unchanged. There is no
        // compile-time coupling in either direction: the shims register Swift classes with the
        // React Native bridge by name at runtime, and none of them imports the generated
        // -Swift.h, so the two targets are siblings rather than a dependency chain.
        .target(
            name: "HyperswitchObjC",
            dependencies: ["React", "ReactNativeHeaders", "ReactNativeDependencies", "hermesvm"],
            path: "hyperswitchSDK/Core",
            sources: [
                "NativeModule/HyperModule.m",
                "NativeModule/HyperHeadless.m",
                "ApplePay/ApplePayViewManager.m"
            ],
            publicHeadersPath: "ObjCInclude"
        ),
        .target(
            name: "Hyperswitch",
            dependencies: [
                "RNInAppBrowser",
                "RNSVG",
                "React",
                "ReactAppDependencyProvider",
                "ReactCodegen",
                "ReactNativeDependencies",
                "React_Codegen",
                "hermesvm",
                "HyperswitchJS",
                // Carries the React_RCTAppDelegate module. React.framework ships
                // RCTReactNativeFactory.h and friends in its Headers but leaves them out of its
                // umbrella, so `import React` never exposes them to Swift and the package could
                // not compile. CocoaPods gets them from the separate React-RCTAppDelegate pod.
                "ReactNativeHeaders",
            ],
            path: "hyperswitchSDK",
            exclude: [
                "CoreLite",
                "AuthenticationModule",
                "Core/NativeModule/HyperModule.m",
                "Core/NativeModule/HyperHeadless.m",
                "Core/ApplePay/ApplePayViewManager.m",
                "Core/ObjCInclude"
            ],
            sources: ["Core", "Shared"]
        ),

        // ----- netcetera3ds -------------------------------------------------------------------
        // ThreeDS_SDK and HyperswitchScanCard are vendored, not built here, and do not change between
        // SDK releases. They are referenced from the `vendor-frameworks` release -- the same zips
        // build-lib.sh's ensure_vendored puts into the pod archive -- rather than re-uploaded with
        // every version, so spm-release.sh leaves these two url:s alone.
        //
        // They must never be path: targets. The xcframeworks are gitignored, so a path: target is
        // absent from every checkout and tag, and SwiftPM then refuses to resolve the WHOLE package
        // -- core-only users included -- with "does not contain a binary artifact".
        //
        // NEVER replace an asset on the vendor-frameworks release (no --clobber): the checksums
        // below would stop matching and every SPM consumer would fail to resolve. A new vendored
        // version goes on a new release tag, with the url and checksum updated here.
        .binaryTarget(
            name: "ThreeDS_SDK",
            url: "https://github.com/peach-payments/hyperswitch-sdk-ios/releases/download/vendor-frameworks/ThreeDS_SDK.xcframework.zip",
            checksum: "b3d8c334e2b9f125decc98ac67e66b57196bca59f4894e17ad57d9e359387083"
        ),
        // Same split as Hyperswitch / HyperswitchObjC: SPM has no mixed-language targets, and the
        // .m is a React Native bridge shim that registers the Swift class by name at runtime.
        // The sources stay where the podspec globs them, so CocoaPods is unchanged.
        .target(
            name: "HyperswitchNetcetera3dsBridgeObjC",
            dependencies: ["React", "ReactNativeHeaders", "ReactNativeDependencies", "hermesvm"],
            path: "frameworkgen/3ds/Source",
            sources: ["HyperswitchNetcetera3ds.m"],
            publicHeadersPath: "ObjCInclude"
        ),
        // Depends on Hyperswitch although no source imports it, mirroring the podspec, where
        // netcetera3ds and scancard depend on core. The bridge is only ever called by core's JS
        // bundle, so adding this product alone must still bring core in. The scancard bridge below
        // follows suit.
        .target(
            name: "HyperswitchNetcetera3dsBridge",
            dependencies: [
                "Hyperswitch",
                "React",
                "ReactNativeHeaders",
                "ReactNativeDependencies",
                "hermesvm",
                "ThreeDS_SDK",
            ],
            path: "frameworkgen/3ds/Source",
            exclude: ["HyperswitchNetcetera3ds.m", "HyperswitchNetcetera3ds-Bridging-Header.h", "ObjCInclude"],
            sources: ["HyperswitchNetcetera3ds.swift", "HyperswitchChallengeManager.swift"]
        ),

        // ----- scancard -----------------------------------------------------------------------
        // From the vendor-frameworks release; see ThreeDS_SDK above.
        .binaryTarget(
            name: "HyperswitchScanCard",
            url: "https://github.com/peach-payments/hyperswitch-sdk-ios/releases/download/vendor-frameworks/HyperswitchScanCard.xcframework.zip",
            checksum: "461a17b8b2d75a0f176875ffdd27beac70e8dfa93d49e4fb8bcef278cbca8d51"
        ),
        .target(
            name: "HyperswitchScancardBridgeObjC",
            dependencies: ["React", "ReactNativeHeaders", "ReactNativeDependencies", "hermesvm"],
            path: "frameworkgen/scanCard/Source",
            sources: ["HyperswitchScancard.m"],
            publicHeadersPath: "ObjCInclude"
        ),
        .target(
            name: "HyperswitchScancardBridge",
            dependencies: [
                "Hyperswitch",
                "React",
                "ReactNativeHeaders",
                "ReactNativeDependencies",
                "hermesvm",
                "HyperswitchScanCard",
            ],
            path: "frameworkgen/scanCard/Source",
            exclude: ["HyperswitchScancard.m", "HyperswitchScancard-Bridging-Header.h", "ObjCInclude"],
            sources: ["HyperswitchScancard.swift"]
        ),
    ]
)
