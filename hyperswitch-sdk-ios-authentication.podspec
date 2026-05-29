version = "0.1.0"

Pod::Spec.new do |s|
  s.name                      = 'hyperswitch-sdk-ios-authentication'
  s.version                   =  version
  s.summary                   = 'Hyperswitch Authentication SDK'
  s.description               = 'Authentication module for Hyperswitch SDK - handles 3DS authentication flows'
  s.homepage                  = 'https://hyperswitch.io/'
  s.author                    = 'Hyperswitch'
  s.license                   = { type: 'Apache-2.0', file: 'LICENSE' }
  s.platform                  = :ios
  s.ios.deployment_target     = '15.1'
  s.swift_version             = '5.0'
  s.source                    = { :http => "https://github.com/peach-payments/hyperswitch-sdk-ios/releases/download/v#{s.version}/hyperswitch-sdk-ios-#{s.version}.zip" }
  s.module_name               = 'HyperswitchAuthentication'

  s.subspec 'core' do |core|
    core.source_files = 'hyperswitchSDK/AuthenticationModule/**/*.{m,swift,h}'
    core.dependency 'hyperswitch-sdk-ios-authentication/common'
  end

  s.subspec 'netcetera3ds' do |netcetera3ds|
    netcetera3ds.source_files = 'frameworkgen/3ds/Source/**/*.{m,swift,h}'
    netcetera3ds.vendored_frameworks = 'frameworkgen/3ds/Frameworks/ThreeDS_SDK.xcframework'
    netcetera3ds.dependency 'hyperswitch-sdk-ios-authentication/core'
  end

  # NOTE: the `trident` and `cardinal` subspecs were dropped from this fork. Their providers
  # (TridentProvider.swift / CardinalProvider.swift) compile via `#if canImport(...)` guards, so
  # `core` builds without them, but the external pods Trident3DS / CardinalMobile are not on the
  # CocoaPods CDN. Re-add the subspecs (and have consumers add the vendor spec sources) if those
  # 3DS providers are shipped.

  s.subspec 'common' do |common|
    common.source_files = 'hyperswitchSDK/Shared/**/*.{m,swift,h}'
  end

  s.default_subspec = 'core', 'common'
end
