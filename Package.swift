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
            url: "https://github.com/peach-payments/hyperswitch-sdk-ios/releases/download/v0.9.0/HyperswitchJS.xcframework.zip",
            checksum: "ae6b478946b3db0c21b5f059071071276b3b08de3a1a1c125d4006b74d2b44c0"
        ),
        .binaryTarget(
            name: "RNInAppBrowser",
            url: "https://github.com/peach-payments/hyperswitch-sdk-ios/releases/download/v0.9.0/RNInAppBrowser.xcframework.zip",
            checksum: "2a0567be541b0ecf611207525167a29bff1f2677a27d64cac9c3add4ad0332f4"
        ),
        .binaryTarget(
            name: "RNSVG",
            url: "https://github.com/peach-payments/hyperswitch-sdk-ios/releases/download/v0.9.0/RNSVG.xcframework.zip",
            checksum: "d3db18d30c2b0b7345253b757d97006454053c414f434c166bd31e1c112d673f"
        ),
        .binaryTarget(
            name: "React",
            url: "https://github.com/peach-payments/hyperswitch-sdk-ios/releases/download/v0.9.0/React.xcframework.zip",
            checksum: "ebc01f1733689db8cb0bf74cc12437e4c4a736620db92c40de35717dd2927f9e"
        ),
        .binaryTarget(
            name: "ReactNativeHeaders",
            url: "https://github.com/peach-payments/hyperswitch-sdk-ios/releases/download/v0.9.0/ReactNativeHeaders.xcframework.zip",
            checksum: "8073552b7823e86a955ca5508079ad37969f3f4812402d1414567d28b197596c"
        ),
        .binaryTarget(
            name: "ReactAppDependencyProvider",
            url: "https://github.com/peach-payments/hyperswitch-sdk-ios/releases/download/v0.9.0/ReactAppDependencyProvider.xcframework.zip",
            checksum: "c2d685e2c9005f42cab8b10242129958150d8db0acd49958c0b22bfd8fbaaba2"
        ),
        .binaryTarget(
            name: "ReactCodegen",
            url: "https://github.com/peach-payments/hyperswitch-sdk-ios/releases/download/v0.9.0/ReactCodegen.xcframework.zip",
            checksum: "99678006d47a6d707694a70e41179fd7c7d3d0c58c9e6697f231b1d04c9b0521"
        ),
        .binaryTarget(
            name: "ReactNativeDependencies",
            url: "https://github.com/peach-payments/hyperswitch-sdk-ios/releases/download/v0.9.0/ReactNativeDependencies.xcframework.zip",
            checksum: "26c7772eb7039a157de38aee62b2194a3029c09bf1b0505c7bbb7974ed2c61c5"
        ),
        .binaryTarget(
            name: "React_Codegen",
            url: "https://github.com/peach-payments/hyperswitch-sdk-ios/releases/download/v0.9.0/React_Codegen.xcframework.zip",
            checksum: "6aea81c1a45ded017f8d631d34ef886d015665183abdac6fa6396d3d152fcbd9"
        ),
        .binaryTarget(
            name: "hermesvm",
            url: "https://github.com/peach-payments/hyperswitch-sdk-ios/releases/download/v0.9.0/hermesvm.xcframework.zip",
            checksum: "ed64a0d82b48324d842864662623cb7cfb815ae530bad12532b69e740333fc22"
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
