version = "0.8.4"

Pod::Spec.new do |s|
  s.name                      = 'peachpayments-hyperswitch-ios'
  s.version                   =  version
  s.summary                   = 'Hyperswitch SDK'
  s.description               = 'Core of Hyperswitch SDK an open-source payments switch'
  s.homepage                  = 'https://hyperswitch.io/'
  s.author                    = 'Harshit S'
  s.license                   = { type: 'Apache-2.0', file: 'LICENSE' }
  s.platform                  = :ios
  s.ios.deployment_target     = '15.1'
  s.swift_version             = '5.0'
  s.source                    = { :http => "https://github.com/peach-payments/hyperswitch-sdk-ios/releases/download/v#{s.version}/hyperswitch-sdk-ios-#{s.version}.zip" }
  s.module_name               = 'Hyperswitch'

  # React.framework is vendored as a prebuilt binary, and its own headers include
  # RCTDeprecation/RCTDeprecation.h, yoga/Yoga.h, react/runtime/JSRuntimeFactoryCAPI.h and
  # five more BY PATH. Those live in the flattened tree under frameworkgen/Frameworks/
  # ReactNative/Headers, so two things have to be true wherever the React module is built:
  #
  #   HEADER_SEARCH_PATHS  - so the includes resolve at all. Without it the build fails with
  #                          "'RCTDeprecation/RCTDeprecation.h' file not found" and then
  #                          "could not build Objective-C module 'React'".
  #   the warning disabled - the tree is deliberately NOT module-mapped (a loose module map
  #                          on a search path breaks resolution of os, Security, CoreData,
  #                          CoreMedia and Network), so these includes are non-modular by
  #                          construction. CocoaPods compiles with -Werror, which turns the
  #                          resulting warning into 8 hard errors.
  #
  # Both are declared here rather than on the `reactnative` subspec: a subspec's
  # pod_target_xcconfig does not reach the target that builds a vendored framework's module.
  # user_target_xcconfig carries the same to the consuming app, which builds the React
  # module itself when it imports Hyperswitch.
  # The warning is suppressed through OTHER_CFLAGS rather than
  # CLANG_WARN_NON_MODULAR_INCLUDE_IN_FRAMEWORK_MODULE. That build setting is already set to
  # YES_ERROR on the generated target, which wins over an xcconfig, so it emits
  # -Werror=non-modular-include-in-framework-module regardless of what we ask for -- verified:
  # with the setting in place, -Wno-non-modular-include-in-framework-module never reached the
  # command line, while HEADER_SEARCH_PATHS from the same dictionary did (29 -I occurrences).
  # A flag appended to OTHER_CFLAGS lands after the -Werror= one, and the last flag wins.
  # $(inherited) matters: CocoaPods merges every pod's flags into this setting.
  s.pod_target_xcconfig = {
    'HEADER_SEARCH_PATHS' => '$(inherited) "${PODS_TARGET_SRCROOT}/frameworkgen/Frameworks/ReactNative/Headers"',
    'OTHER_CFLAGS' => '$(inherited) -Wno-non-modular-include-in-framework-module',
    'OTHER_SWIFT_FLAGS' => '$(inherited) -Xcc -Wno-non-modular-include-in-framework-module'
  }
  # The consuming app builds the React module too, the moment it imports Hyperswitch --
  # and so does any *other* pod that imports it, which is how the Flutter plugin consumes
  # this SDK. Those targets need the header tree as well, not just the warning flags:
  # without it, building the React module fails on <RCTDeprecation/RCTDeprecation.h>.
  s.user_target_xcconfig = {
    'HEADER_SEARCH_PATHS' => '$(inherited) "${PODS_ROOT}/peachpayments-hyperswitch-ios/frameworkgen/Frameworks/ReactNative/Headers" "${PODS_TARGET_SRCROOT}/frameworkgen/Frameworks/ReactNative/Headers"',
    'OTHER_CFLAGS' => '$(inherited) -Wno-non-modular-include-in-framework-module',
    'OTHER_SWIFT_FLAGS' => '$(inherited) -Xcc -Wno-non-modular-include-in-framework-module'
  }

  # React Native 0.87 ships its core prebuilt rather than compiling it into the host app,
  # so it is vendored here: React.xcframework (the compiled core, carrying the <React/...>
  # headers and the framework module map), ReactNativeDependencies.xcframework, and
  # hermesvm.xcframework. Headers/ holds the <react/...>, <yoga/...> and folly/glog/boost
  # namespaces those modules include, flattened exactly as the upstream pods do.
  #
  # The binaries are vendored by `core`. This subspec carries only the header trees, and
  # deliberately does NOT declare them as source_files / public_header_files.
  #
  # React.framework ships its own module map, so `import React` finds the module; what
  # fails is BUILDING it, because its umbrella header reaches for RCTDeprecation,
  # <react/...>, <yoga/...> and folly/glog/boost. Those headers therefore have to be
  # reachable -- but only on an include path, not as part of this pod's module.
  #
  # Declaring them as public headers folds 35 namespaces into the single module map and
  # umbrella header CocoaPods generates for peachpayments-hyperswitch-ios, which poisons
  # clang's module graph: `os`, `Security`, `CoreData`, `CoreMedia` and `Network` all stop
  # resolving. A plain HEADER_SEARCH_PATHS entry has none of that effect, provided the
  # module.modulemap at the root of React-Core-prebuilt's tree is excluded when the tree is
  # vendored (framework.sh does this) -- a loose module map on a search path is what
  # actually disturbs module resolution.
  #
  # Verified directly: `import React` plus all five system modules above compile against a
  # framework search path + this include path, and fail without it with
  # "'RCTDeprecation/RCTDeprecation.h' file not found / could not build module 'React'".
  #
  # pod_target_xcconfig applies to the whole pod target, so `core`'s sources -- the 14 files
  # that import React -- pick the path up through this subspec being a dependency.
  s.subspec 'reactnative' do |rn|
    rn.preserve_paths      = 'frameworkgen/Frameworks/ReactNative/**/*'
  end

  s.subspec 'core' do |core|
    core.source_files = 'hyperswitchSDK/Core/**/*.{m,swift,h}'
    core.resources = ['hyperswitchSDK/Core/Resources/HyperOTA.plist', 'hyperswitchSDK/Core/Resources/hyperswitch.bundle']
    core.vendored_frameworks = 'frameworkgen/Frameworks/Core/*.xcframework'
    core.dependency 'peachpayments-hyperswitch-ios/common'
    core.dependency 'peachpayments-hyperswitch-ios/reactnative'
    # hyperswitch-ios-hermes is gone: it only exists at 0.79.1, which is the Hermes built
    # for React Native 0.79. 0.87 requires Hermes 250829098.0.17, now vendored above as
    # hermesvm.xcframework straight from the hermes-engine pod the build resolves.
  end

  s.subspec 'scancard' do |scancard|
    scancard.source_files = 'frameworkgen/scanCard/Source/**/*.{m,swift,h}'
    scancard.vendored_frameworks = 'frameworkgen/scanCard/Frameworks/*.xcframework'
    scancard.dependency 'peachpayments-hyperswitch-ios/core'
  end

  s.subspec 'netcetera3ds' do |netcetera3ds|
    netcetera3ds.source_files = 'frameworkgen/3ds/Source/**/*.{m,swift,h}'
    netcetera3ds.vendored_frameworks = 'frameworkgen/3ds/Frameworks/*.xcframework'
    netcetera3ds.dependency 'peachpayments-hyperswitch-ios/core'
  end

  # The 'airborne' and 'paypal' subspecs were removed in 0.8.3.
  #
  # Both pinned dependencies that declare deployment targets Xcode 27 no longer accepts --
  # HyperOTA at iOS 12.0, PayPal 2.x at iOS 14.0, against a floor of 15.0 -- so `pod lib lint`
  # failed on them and no release could be cut. An app build was unaffected, because this repo's
  # Podfile raises those targets in post_install, but lint builds in its own sandbox and never
  # sees it, and a podspec cannot raise a dependency's deployment target. HyperOTA 0.0.8 is still
  # the newest published version, so there was nothing to upgrade to.
  #
  # Neither was reachable in practice: paypal was referenced by nothing, airborne only by
  # peachpayments_flutter_airborne, which is publish_to: none. Neither was in default_subspec, so
  # no merchant got either without asking for it by name.
  #
  # The OTA code paths in the SDK are guarded by `#if canImport(HyperOTA)` and simply take their
  # else branch now. frameworkgen/paypal/Source is left in the tree; restoring either subspec is
  # a podspec edit once the upstream pods ship supported deployment targets.

  s.subspec 'common' do |common|
    common.source_files = 'hyperswitchSDK/Shared/**/*.{m,swift,h}'
  end

  s.default_subspec = 'core', 'common'
end
