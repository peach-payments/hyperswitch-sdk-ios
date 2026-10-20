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
    products: [
        .library(name: "Hyperswitch", targets: ["Hyperswitch", "HyperswitchObjC"])
    ],
    targets: [
        .binaryTarget(
            name: "RNInAppBrowser",
            url: "https://github.com/peach-payments/hyperswitch-sdk-ios/releases/download/v0.8.1/RNInAppBrowser.xcframework.zip",
            checksum: "b8bd969e988c2b47fdcf794d70829ca9da75adcc18a66cb1f6dff2dee819f170"
        ),
        .binaryTarget(
            name: "RNSVG",
            url: "https://github.com/peach-payments/hyperswitch-sdk-ios/releases/download/v0.8.1/RNSVG.xcframework.zip",
            checksum: "df0f2d107c955c4d12f5c453f856e4f430d3cd50815571aa693df054ec817bef"
        ),
        .binaryTarget(
            name: "React",
            url: "https://github.com/peach-payments/hyperswitch-sdk-ios/releases/download/v0.8.1/React.xcframework.zip",
            checksum: "6f9ec52071622d661e6d51babc7c3d96669c98293de787354c2675e35c7781c0"
        ),
        .binaryTarget(
            name: "ReactNativeHeaders",
            url: "https://github.com/peach-payments/hyperswitch-sdk-ios/releases/download/v0.8.1/ReactNativeHeaders.xcframework.zip",
            checksum: "e508345b5d3e98d7f473f97aa4a6daf8fe3de7c69a49fdf2592cce38cb806edb"
        ),
        .binaryTarget(
            name: "ReactAppDependencyProvider",
            url: "https://github.com/peach-payments/hyperswitch-sdk-ios/releases/download/v0.8.1/ReactAppDependencyProvider.xcframework.zip",
            checksum: "5949e7e320cbdc7337cb0d79be2b24b1a765764e158386ef058a0dd7c8e0e4a1"
        ),
        .binaryTarget(
            name: "ReactCodegen",
            url: "https://github.com/peach-payments/hyperswitch-sdk-ios/releases/download/v0.8.1/ReactCodegen.xcframework.zip",
            checksum: "4a47366cf565a9b17d990135b401880d75b3fbd554ff49f1d1e91d2b5e3d94df"
        ),
        .binaryTarget(
            name: "ReactNativeDependencies",
            url: "https://github.com/peach-payments/hyperswitch-sdk-ios/releases/download/v0.8.1/ReactNativeDependencies.xcframework.zip",
            checksum: "aa039f379aa9679726d2ad06c24036a3642dab860eded86e616bb7248744f35c"
        ),
        .binaryTarget(
            name: "React_Codegen",
            url: "https://github.com/peach-payments/hyperswitch-sdk-ios/releases/download/v0.8.1/React_Codegen.xcframework.zip",
            checksum: "285ee6b29015d25d596451732772a5b57c82cd81e9cee204e59b9e3d2c8c8530"
        ),
        .binaryTarget(
            name: "hermesvm",
            url: "https://github.com/peach-payments/hyperswitch-sdk-ios/releases/download/v0.8.1/hermesvm.xcframework.zip",
            checksum: "55c4c6397db69438df97923ac70f616971e24cd8c8be3f5c336aaa15999f70fb"
        ),
        .binaryTarget(
            name: "react_native_hyperswitch_netcetera_3ds",
            url: "https://github.com/peach-payments/hyperswitch-sdk-ios/releases/download/v0.8.1/react_native_hyperswitch_netcetera_3ds.xcframework.zip",
            checksum: "38e41d85d8b78ab8c80fc8e51bedc97ac288633807a30f63da345c197fbd10d9"
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
                "react_native_hyperswitch_netcetera_3ds",
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
