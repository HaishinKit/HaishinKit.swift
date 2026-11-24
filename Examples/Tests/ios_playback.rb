#!/usr/bin/env ruby
# Test the actual iOS sample models in a temporary, tool-hosted simulator test bundle.
require 'fileutils'
require 'json'
require 'tmpdir'

abort 'Usage: ruby Examples/Tests/ios_playback.rb SIMULATOR_UDID' unless ARGV.length == 1
root = File.expand_path('../..', __dir__)
Dir.mktmpdir('haishinkit-ios-playback-') do |directory|
  sources = File.join(directory, 'Tests', 'PlaybackTests')
  FileUtils.mkdir_p(sources)
  %w[PlaybackViewModel.swift PreferenceViewModel.swift].each do |name|
    FileUtils.cp(File.join(root, 'Examples/iOS', name), sources)
  end
  FileUtils.cp(File.join(root, 'Examples/Preference.swift'), sources)
  FileUtils.cp(File.join(__dir__, 'IOSPlaybackTests.swift'), sources)
  # Keep test-only access out of the shipped application and public library API.
  File.open(File.join(sources, 'PlaybackViewModel.swift'), 'a') do |file|
    file.write <<~SWIFT
      extension PlaybackViewModel {
          var testedSession: (any StreamSession)? { session }
          var testedPiPLayer: AVSampleBufferDisplayLayer? { pictureInPictureController?.contentSource?.sampleBufferDisplayLayer }
      }
    SWIFT
  end
  File.write(File.join(directory, 'Package.swift'), <<~SWIFT)
    // swift-tools-version:6.0
    import PackageDescription
    let package = Package(name: "IOSPlayback", platforms: [.iOS(.v16)],
        dependencies: [.package(name: "HaishinKit.swift", path: #{JSON.generate(root)})],
        targets: [.testTarget(name: "PlaybackTests", dependencies: [
            .product(name: "HaishinKit", package: "HaishinKit.swift")
        ])], swiftLanguageModes: [.v5])
  SWIFT
  Dir.chdir(directory) do
    command = ['xcodebuild', '-scheme', 'IOSPlayback-Package', '-destination', "platform=iOS Simulator,id=#{ARGV.fetch(0)}",
               '-jobs', '4', 'CODE_SIGNING_ALLOWED=NO', 'test']
    abort 'iOS playback regression tests failed.' unless system(*command)
  end
end
