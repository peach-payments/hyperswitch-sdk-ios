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
            url: "https://github.com/peach-payments/hyperswitch-sdk-ios/releases/download/v0.8.0/RNInAppBrowser.xcframework.zip",
            checksum: "e988e708b1ace4ca60f07a081bd192305ec6120e9f9d1f394876821159f23327"
        ),
        .binaryTarget(
            name: "RNSVG",
            url: "https://github.com/peach-payments/hyperswitch-sdk-ios/releases/download/v0.8.0/RNSVG.xcframework.zip",
            checksum: "a3d74b8c6bf9593f826c08b7b1e6375f2eb9228fa61150fb7b42e2b35b755f47"
        ),
        .binaryTarget(
            name: "React",
            url: "https://github.com/peach-payments/hyperswitch-sdk-ios/releases/download/v0.8.0/React.xcframework.zip",
            checksum: "8a78b3d6999f150c9c9288f988aa58858ab6a332c4d9448195e5976682abc31e"
        ),
        .binaryTarget(
            name: "ReactNativeHeaders",
            url: "https://github.com/peach-payments/hyperswitch-sdk-ios/releases/download/v0.8.0/ReactNativeHeaders.xcframework.zip",
            checksum: "61dc5e953396c1e7e45c6a2040a1f4d0a6e864ec4bbcd13a0ecf8978247da0e5"
        ),
        .binaryTarget(
            name: "ReactAppDependencyProvider",
            url: "https://github.com/peach-payments/hyperswitch-sdk-ios/releases/download/v0.8.0/ReactAppDependencyProvider.xcframework.zip",
            checksum: "8fac503af0b4efc305baeba1a71ef776947965257f89a100dbc3e70445194541"
        ),
        .binaryTarget(
            name: "ReactCodegen",
            url: "https://github.com/peach-payments/hyperswitch-sdk-ios/releases/download/v0.8.0/ReactCodegen.xcframework.zip",
            checksum: "88e9d40eb69982cb593d9d8971e03dacaa8ed13165bdd929b6230561888e867f"
        ),
        .binaryTarget(
            name: "ReactNativeDependencies",
            url: "https://github.com/peach-payments/hyperswitch-sdk-ios/releases/download/v0.8.0/ReactNativeDependencies.xcframework.zip",
            checksum: "86431e2eed299dd39c97d32f037bfead3e4dc26feda13f25fea29f86c9cf9158"
        ),
        .binaryTarget(
            name: "React_Codegen",
            url: "https://github.com/peach-payments/hyperswitch-sdk-ios/releases/download/v0.8.0/React_Codegen.xcframework.zip",
            checksum: "bbff1defffe738bc25efb6186f122ead1875a8aa285352895d7baed75fa36a39"
        ),
        .binaryTarget(
            name: "hermesvm",
            url: "https://github.com/peach-payments/hyperswitch-sdk-ios/releases/download/v0.8.0/hermesvm.xcframework.zip",
            checksum: "59520a43ef8509df61e950bb1088913271d8c582d95e2159227828da46adb0a2"
        ),
        .binaryTarget(
            name: "react_native_hyperswitch_netcetera_3ds",
            url: "https://github.com/peach-payments/hyperswitch-sdk-ios/releases/download/v0.8.0/react_native_hyperswitch_netcetera_3ds.xcframework.zip",
            checksum: "e85f9e2376e09f256994ef7227d97b0281f0418b1f914142c3d6c712ca8a1009"
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
