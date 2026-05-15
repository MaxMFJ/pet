macos_deployment_target = '13.0'
ios_deployment_target = '16.0'

platform :osx, macos_deployment_target
install! 'cocoapods', :warn_for_unused_master_specs_repo => false

project 'DesktopPet.xcodeproj'

target 'DesktopPet' do
  use_frameworks! :linkage => :static

  # Optional next-step dependencies:
  # pod 'SDWebImage', '~> 5.19'
  # pod 'SDWebImageWebPCoder', '~> 0.14'
  # pod 'AFNetworking', '~> 4.0'
end

target 'DesktopPetiOS' do
  use_frameworks! :linkage => :static
  pod 'SSZipArchive', '~> 2.5'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = macos_deployment_target
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = ios_deployment_target
    end
  end
end
