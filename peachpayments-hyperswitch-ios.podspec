version = "0.8.0"

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

  # React Native 0.87 ships its core prebuilt rather than compiling it into the host app,
  # so it is vendored here: React.xcframework (the compiled core, carrying the <React/...>
  # headers and the framework module map), ReactNativeDependencies.xcframework, and
  # hermesvm.xcframework. Headers/ holds the <react/...>, <yoga/...> and folly/glog/boost
  # namespaces those modules include, flattened exactly as the upstream pods do.
  #
  # The binaries are vendored by `core` (alongside the SDK's own sources, which is what
  # makes `import React` resolve); this subspec carries only the header trees, so that the
  # header_mappings_dir needed to preserve <react/...> nesting does not disturb core.
  s.subspec 'reactnative' do |rn|
    rn.preserve_paths      = 'frameworkgen/Frameworks/ReactNative/**/*'
    rn.header_mappings_dir = 'frameworkgen/Frameworks/ReactNative/Headers'
    rn.source_files        = 'frameworkgen/Frameworks/ReactNative/Headers/**/*.{h,hpp}'
    rn.public_header_files = 'frameworkgen/Frameworks/ReactNative/Headers/**/*.h'
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

  s.subspec 'sentry' do |sentry|
    sentry.vendored_frameworks = 'frameworkgen/Frameworks/Sentry/*.xcframework'
    sentry.dependency 'peachpayments-hyperswitch-ios/core'
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

  s.subspec 'airborne' do |airborne|
    airborne.dependency 'HyperOTA', '0.0.8'
    airborne.dependency 'peachpayments-hyperswitch-ios/core'
  end

  s.subspec 'paypal' do |paypal|
    paypal.source_files = 'frameworkgen/paypal/Source/**/*.{h,m,mm,swift}'
    paypal.dependency "PayPal/CardPayments", "~> 2.0"
    paypal.dependency "PayPal/PaymentButtons", "~> 2.0"
    paypal.dependency "PayPal/PayPalWebPayments", "~> 2.0"   
    paypal.dependency 'peachpayments-hyperswitch-ios/core'
  end

  s.subspec 'common' do |common|
    common.source_files = 'hyperswitchSDK/Shared/**/*.{m,swift,h}'
  end

  s.default_subspec = 'core', 'common'
end
