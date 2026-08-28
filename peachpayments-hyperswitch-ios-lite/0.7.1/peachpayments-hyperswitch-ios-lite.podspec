version = "0.7.1"

Pod::Spec.new do |s|
  s.name                      = 'peachpayments-hyperswitch-ios-lite'
  s.version                   =  version
  s.summary                   = 'Hyperswitch SDK Lite'
  s.description               = 'Core of Hyperswitch SDK Lite an open-source payments switch'
  s.homepage                  = 'https://hyperswitch.io/'
  s.author                    = 'Harshit S'
  s.license                   = { type: 'Apache-2.0', file: 'LICENSE' }
  s.platform                  = :ios
  s.ios.deployment_target     = '15.1'
  s.swift_version             = '5.0'
  s.source                    = { :http => "https://github.com/peach-payments/hyperswitch-sdk-ios/releases/download/v#{s.version}/hyperswitch-sdk-ios-#{s.version}.zip" }
  s.module_name               = 'HyperswitchLite'

  s.subspec 'core' do |core|
    core.source_files = 'hyperswitchSDK/CoreLite/*.{m,swift,h}'
    core.dependency 'peachpayments-hyperswitch-ios-lite/common'
  end

  s.subspec 'scancard' do |scancard|
    scancard.vendored_frameworks = 'frameworkgen/scanCard/Frameworks/*.xcframework'
    scancard.dependency 'peachpayments-hyperswitch-ios-lite/core'
  end

  s.subspec 'common' do |common|
    common.source_files = 'hyperswitchSDK/Shared/**/*.{m,swift,h}'
  end

  s.default_subspec = 'core', 'common'
end

