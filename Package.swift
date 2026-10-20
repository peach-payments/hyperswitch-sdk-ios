// swift-tools-version:5.9
import PackageDescription

// Swift Package Manager distribution, alongside CocoaPods.
//
// The xcframeworks are referenced by path here, which works for a checked-out repo. Remote
// consumption additionally needs a url + checksum per binaryTarget; build-lib.sh has to emit
// one zip and one checksum per xcframework for that, which is tracked separately.
//
// React Native 0.87 ships its core prebuilt, so React.xcframework and friends are vendored
// rather than compiled. Building the React module needs the flattened <react/...>, <yoga/...>
// and folly/glog/boost headers on an include path -- the same requirement the podspec has.
// headerSearchPath may leave the target but not the package, which our layout satisfies.
//
// INCOMPLETE -- this manifest does not build yet, and cannot in its present shape.
//
// React.framework's headers include RCTDeprecation/..., yoga/Yoga.h and six more BY PATH,
// against a header tree that is deliberately not module-mapped. Building the React module
// therefore raises -Werror=non-modular-include-in-framework-module, exactly as it does under
// CocoaPods. The podspec suppresses it with OTHER_CFLAGS; SPM's only equivalent is
// .unsafeFlags, which it forbids for packages consumed by version -- i.e. the way merchants
// would add this one. Using it would make the package undependable.
//
// The route out is to ship hyperswitchSDK/Core as a prebuilt xcframework, so a consumer never
// builds the React module at all; ours already did. That needs a frameworkgen target which
// does not exist today, and it costs module stability (BUILD_LIBRARY_FOR_DISTRIBUTION),
// constraining which Swift versions merchants can build with. That trade is not ours to make
// unilaterally, so it is left open.
//
// What is already settled and worth keeping: binaryTargets consume the vendored xcframeworks,
// headerSearchPath may leave a target but not the package (our layout satisfies that), the
// three Objective-C bridge shims are split into a sibling target because SPM has no
// mixed-language targets, and the Swift sources no longer depend on hyper-Bridging-Header.h,
// which SPM cannot provide.
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
