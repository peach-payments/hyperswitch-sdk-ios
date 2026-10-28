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
        .binaryTarget(
            name: "RNInAppBrowser",
            url: "https://github.com/peach-payments/hyperswitch-sdk-ios/releases/download/v0.8.3/RNInAppBrowser.xcframework.zip",
            checksum: "67a67dca4f5fa8deb867ef9a0e18b58bc9170ed6dbb8ca3faf9147a4466edc39"
        ),
        .binaryTarget(
            name: "RNSVG",
            url: "https://github.com/peach-payments/hyperswitch-sdk-ios/releases/download/v0.8.3/RNSVG.xcframework.zip",
            checksum: "92011c04789b3342e8daf595b6551467d88b01b9e3af8d8a877d8d6d7b1cdc36"
        ),
        .binaryTarget(
            name: "React",
            url: "https://github.com/peach-payments/hyperswitch-sdk-ios/releases/download/v0.8.3/React.xcframework.zip",
            checksum: "7d16611e214b4e2451b1a66b919d0583ea6561d18148f23975630815a0014abf"
        ),
        .binaryTarget(
            name: "ReactNativeHeaders",
            url: "https://github.com/peach-payments/hyperswitch-sdk-ios/releases/download/v0.8.3/ReactNativeHeaders.xcframework.zip",
            checksum: "18e19f5590cb2a51264570edf4a0b4ff976d33e74051423702c1e42ddf20f9a3"
        ),
        .binaryTarget(
            name: "ReactAppDependencyProvider",
            url: "https://github.com/peach-payments/hyperswitch-sdk-ios/releases/download/v0.8.3/ReactAppDependencyProvider.xcframework.zip",
            checksum: "f3e8a87ac3aa97ebc1764b4d5f268fdd622bdc08e81370a446463a9f49f3a3bf"
        ),
        .binaryTarget(
            name: "ReactCodegen",
            url: "https://github.com/peach-payments/hyperswitch-sdk-ios/releases/download/v0.8.3/ReactCodegen.xcframework.zip",
            checksum: "7fde8dd899cf1d1dd3c8bdc397d0d9c819ba0ef5b682e5b82de219377b438f8f"
        ),
        .binaryTarget(
            name: "ReactNativeDependencies",
            url: "https://github.com/peach-payments/hyperswitch-sdk-ios/releases/download/v0.8.3/ReactNativeDependencies.xcframework.zip",
            checksum: "07044009fafc8162d73b575769ed4979adc86a1f151369a2ffcd287634cdd982"
        ),
        .binaryTarget(
            name: "React_Codegen",
            url: "https://github.com/peach-payments/hyperswitch-sdk-ios/releases/download/v0.8.3/React_Codegen.xcframework.zip",
            checksum: "8f755db811143bed40eee4c547d3a934ce3f84b17a20c47aa4e4fe6a6db20085"
        ),
        .binaryTarget(
            name: "hermesvm",
            url: "https://github.com/peach-payments/hyperswitch-sdk-ios/releases/download/v0.8.3/hermesvm.xcframework.zip",
            checksum: "e39a0593aa9d182c82c8dd39f4d765d7798e995173a9075b64743d55aed89e73"
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
