Pod::Spec.new do |s|

  s.name          = "HaishinKit"
  s.version       = "1.9.9"
  s.summary       = "Camera and Microphone streaming library via RTMP for iOS, macOS, tvOS and visionOS."
  s.swift_version = "5.10"

  s.description  = <<-DESC
  HaishinKit. Camera and Microphone streaming library via RTMP for iOS, macOS, tvOS and visionOS.
  DESC

  s.homepage     = "https://github.com/shogo4405/HaishinKit.swift"
  s.license      = "New BSD"
  s.author       = { "shogo4405" => "shogo4405@gmail.com" }
  s.authors      = { "shogo4405" => "shogo4405@gmail.com" }
  s.source       = { :git => "https://github.com/shogo4405/HaishinKit.swift.git", :tag => "#{s.version}" }

  s.ios.deployment_target = "13.0"
  s.osx.deployment_target = "10.15"
  s.tvos.deployment_target = "13.0"
  s.visionos.deployment_target = "1.0"
  s.source_files = "Sources/**/*.swift", "Platforms/*.{h,swift}"
  s.dependency 'Logboard', '~> 2.5.0'

end
