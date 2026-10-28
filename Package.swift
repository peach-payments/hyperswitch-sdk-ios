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
    // The Netcetera 3DS module is deliberately absent. It links ThreeDS_SDK, which is a separate
    // vendored framework, and CocoaPods ships that pairing as the netcetera3ds subspec rather than
    // in core. Keeping it out of a binaryTarget here matches core: a single product that links
    // only what it also ships. Vendoring it without ThreeDS_SDK is what crashed apps at launch in
    // 0.8.0-0.8.2.
    products: [
        .library(name: "Hyperswitch", targets: ["Hyperswitch", "HyperswitchObjC"])
    ],
    targets: [
        // The JavaScript bundle the payment sheet runs, packaged as a framework so it can
        // travel as a binary artifact. CocoaPods ships it through `core.resources` out of the
        // pod archive; SPM takes package source from the git tag, where a build artifact like
        // this one is not committed, so without this the package resolved and compiled and
        // then had no JavaScript to run. Built by frameworkgen/scripts/js-bundle-xcframework.sh.
        .binaryTarget(
            name: "HyperswitchJS",
            url: "https://github.com/peach-payments/hyperswitch-sdk-ios/releases/download/v0.8.4/HyperswitchJS.xcframework.zip",
            checksum: "e8c97fefb6adaedec94b92c17074d82db305eee0a4ef382ee448d90c149c2f58"
        ),
        .binaryTarget(
            name: "RNInAppBrowser",
            url: "https://github.com/peach-payments/hyperswitch-sdk-ios/releases/download/v0.8.4/RNInAppBrowser.xcframework.zip",
            checksum: "88498fd799fba7df0e7177361f12e6dd904bd8db13112588e60efaedae1ff409"
        ),
        .binaryTarget(
            name: "RNSVG",
            url: "https://github.com/peach-payments/hyperswitch-sdk-ios/releases/download/v0.8.4/RNSVG.xcframework.zip",
            checksum: "bb95060a7de38c50fd0e810926d08cd798a9c4cf0dd69653467953fa848ce1a7"
        ),
        .binaryTarget(
            name: "React",
            url: "https://github.com/peach-payments/hyperswitch-sdk-ios/releases/download/v0.8.4/React.xcframework.zip",
            checksum: "1fcf95b189ed91eb56903f1e1655f602a90c9d9bb0ea7759d6f8cc19da5c9c23"
        ),
        .binaryTarget(
            name: "ReactNativeHeaders",
            url: "https://github.com/peach-payments/hyperswitch-sdk-ios/releases/download/v0.8.4/ReactNativeHeaders.xcframework.zip",
            checksum: "051d08fe8cd4b759dc99f68108dd2479daa8a14bbbc8428437f45980e945b877"
        ),
        .binaryTarget(
            name: "ReactAppDependencyProvider",
            url: "https://github.com/peach-payments/hyperswitch-sdk-ios/releases/download/v0.8.4/ReactAppDependencyProvider.xcframework.zip",
            checksum: "59365b6168c51cbbd0b204c2346399c8805c3bd174f8ef491f13739ebdfd1a6f"
        ),
        .binaryTarget(
            name: "ReactCodegen",
            url: "https://github.com/peach-payments/hyperswitch-sdk-ios/releases/download/v0.8.4/ReactCodegen.xcframework.zip",
            checksum: "ae9156142c138a354d18a1905d3b58e1bf94c2c8dc49e3ea601bd280122b914e"
        ),
        .binaryTarget(
            name: "ReactNativeDependencies",
            url: "https://github.com/peach-payments/hyperswitch-sdk-ios/releases/download/v0.8.4/ReactNativeDependencies.xcframework.zip",
            checksum: "9d98a9a47610d90a9b25532380414ea84d88f241b6f0288426f95bc753671ed9"
        ),
        .binaryTarget(
            name: "React_Codegen",
            url: "https://github.com/peach-payments/hyperswitch-sdk-ios/releases/download/v0.8.4/React_Codegen.xcframework.zip",
            checksum: "417cf40c6014e851c4e5b749471b774450f92e7acdd03545c48dcb4a54ad1c6d"
        ),
        .binaryTarget(
            name: "hermesvm",
            url: "https://github.com/peach-payments/hyperswitch-sdk-ios/releases/download/v0.8.4/hermesvm.xcframework.zip",
            checksum: "e656815a28c35a010131c07e3e9433f52ae077314c126fce3f0fc8788c3e8de2"
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
        )
    ]
)
