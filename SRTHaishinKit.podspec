Pod::Spec.new do |s|

  s.name          = "SRTHaishinKit"
  s.version       = "1.9.9"
  s.summary       = "Camera and Microphone streaming library via SRT for iOS, macOS, tvOS and visionOS."
  s.swift_version = "5.10"

  s.description  = <<-DESC
  SRTHaishinKit. Camera and Microphone streaming library via SRT for iOS, macOS, tvOS and visionOS.
  DESC

  s.homepage     = "https://github.com/shogo4405/HaishinKit.swift"
  s.license      = "New BSD"
  s.author       = { "shogo4405" => "shogo4405@gmail.com" }
  s.authors      = { "shogo4405" => "shogo4405@gmail.com" }
  s.source       = { :git => "https://github.com/shogo4405/HaishinKit.swift.git", :tag => "#{s.version}" }

  s.ios.deployment_target = "13.0"
  s.ios.user_target_xcconfig = { 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'x86_64' }
  s.ios.pod_target_xcconfig = { 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'x86_64' }

  # s.osx.deployment_target = "13.0"
  # s.osx.user_target_xcconfig = { 'EXCLUDED_ARCHS[sdk=macosx*]' => 'x86_64' }
  # s.osx.pod_target_xcconfig = { 'EXCLUDED_ARCHS[sdk=macosx*]' => 'x86_64' }

  s.tvos.deployment_target = "13.0"
  s.tvos.user_target_xcconfig = { 'EXCLUDED_ARCHS[sdk=appletvsimulator*]' => 'x86_64' }
  s.tvos.pod_target_xcconfig = { 'EXCLUDED_ARCHS[sdk=appletvsimulator*]' => 'x86_64' }

  # s.visionos.deployment_target = "1.0"

  s.source_files = "SRTHaishinKit/*.{h,swift}"
  s.vendored_frameworks = "Vendor/SRT/libsrt.xcframework"
  s.dependency 'HaishinKit', '1.9.8'

end
