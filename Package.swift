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
        .binaryTarget(name: "RNInAppBrowser", path: "frameworkgen/Frameworks/Core/RNInAppBrowser.xcframework"),
        .binaryTarget(name: "RNSVG", path: "frameworkgen/Frameworks/Core/RNSVG.xcframework"),
        .binaryTarget(name: "React", path: "frameworkgen/Frameworks/Core/React.xcframework"),
        .binaryTarget(name: "ReactNativeHeaders", path: "frameworkgen/Frameworks/ReactNative/ReactNativeHeaders.xcframework"),
        .binaryTarget(name: "ReactAppDependencyProvider", path: "frameworkgen/Frameworks/Core/ReactAppDependencyProvider.xcframework"),
        .binaryTarget(name: "ReactCodegen", path: "frameworkgen/Frameworks/Core/ReactCodegen.xcframework"),
        .binaryTarget(name: "ReactNativeDependencies", path: "frameworkgen/Frameworks/Core/ReactNativeDependencies.xcframework"),
        .binaryTarget(name: "React_Codegen", path: "frameworkgen/Frameworks/Core/React_Codegen.xcframework"),
        .binaryTarget(name: "hermesvm", path: "frameworkgen/Frameworks/Core/hermesvm.xcframework"),
        .binaryTarget(name: "react_native_hyperswitch_netcetera_3ds", path: "frameworkgen/Frameworks/Core/react_native_hyperswitch_netcetera_3ds.xcframework"),
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
