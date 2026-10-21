require Pod::Executable.execute_command('node', ['-p',
  'require.resolve(
    "react-native/scripts/react_native_pods.rb",
    {paths: [process.argv[1]]},
  )', __dir__]).strip

platform :ios, min_ios_version_supported
prepare_react_native_project!

linkage = ENV['USE_FRAMEWORKS']
if linkage != nil
  Pod::UI.puts "Configuring Pod with #{linkage}ally linked Frameworks".green
  use_frameworks! :linkage => linkage.to_sym
end

target 'hyperswitch' do
  config = use_native_modules!
  # pod 'hyperswitch-sdk-ios-authentication/trident', :path => '.'
  pod 'HyperOTA', '0.0.8'
  use_react_native!(
    :path => config[:reactNativePath],
    :hermes_enabled => true,
    :fabric_enabled => false,
    :app_path => "#{Pod::Config.instance.installation_root}/.."
  )

  post_install do |installer|
    react_native_post_install(
      installer,
      config[:reactNativePath],
      :mac_catalyst_enabled => false,
      # :ccache_enabled => true
    )

    # Xcode 27 refuses to build any target whose deployment target is below iOS 15.0:
    #
    #   error: The iOS Simulator deployment target 'IPHONEOS_DEPLOYMENT_TARGET' is set to
    #   12.4, but the range of supported deployment target versions is 15.0 to 27.0.x.
    #   (in target 'RNSVG-RNSVGFilters' from project 'Pods')
    #
    # react_native_post_install raises the pods' own targets, but not the resource-bundle
    # targets CocoaPods generates alongside them -- those keep whatever the podspec asked
    # for, and several dependencies still declare iOS 12.4. That one target was enough to
    # fail the whole build and pin releases to Xcode 26.
    #
    # Raise anything below the floor to the version the SDK itself supports. Pods that
    # already ask for more are left alone, so this only ever moves a target forwards.
    floor = Gem::Version.new(min_ios_version_supported)
    projects = [installer.pods_project]
    projects += installer.generated_projects if installer.respond_to?(:generated_projects)
    projects.compact.uniq.each do |project|
      project.targets.each do |target|
        target.build_configurations.each do |config|
          current = config.build_settings['IPHONEOS_DEPLOYMENT_TARGET']
          if current.nil? || Gem::Version.new(current.to_s) < floor
            config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = min_ios_version_supported
          end
        end
      end
      project.save
    end
  end
end

