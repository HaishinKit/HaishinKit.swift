#!/usr/bin/env ruby
# Exercise the actual macOS capture/package sources with deterministic frames,
# without camera permission. Output can be evaluated by VQMetrix integration tests.
require 'fileutils'
require 'json'
require 'tmpdir'

abort 'Usage: ruby Examples/Tests/vqmetrix_capture.rb OUTPUT_DIRECTORY' unless ARGV.length == 1
root = File.expand_path('../..', __dir__)
output = File.expand_path(ARGV.fetch(0))
# Never replace an existing recording or fixture directory.
abort "Output already exists: #{output}" if File.exist?(output)
FileUtils.mkdir_p(output)
Dir.mktmpdir('vqmetrix-capture-') do |directory|
  sources = File.join(directory, 'Sources', 'Probe')
  FileUtils.mkdir_p(sources)
  %w[VQMetrixCapture.swift VQMetrixSoftwareEncoder.swift VQMetrixTransfer.swift].each do |name|
    FileUtils.cp(File.join(root, 'Examples', 'macOS', name), sources)
  end
  FileUtils.cp(File.join(__dir__, 'VQMetrixCaptureProbe.swift'), File.join(sources, 'Probe.swift'))
  File.write(File.join(directory, 'Package.swift'), <<~SWIFT)
    // swift-tools-version:6.0
    import PackageDescription
    let package = Package(name: "VQMetrixCaptureProbe", platforms: [.macOS(.v15)],
        dependencies: [.package(name: "HaishinKit.swift", path: #{JSON.generate(root)})], targets: [
            .executableTarget(name: "Probe", dependencies: [
                .product(name: "HaishinKit", package: "HaishinKit.swift"),
                .product(name: "AOMHaishinKit", package: "HaishinKit.swift"),
                .product(name: "VPXHaishinKit", package: "HaishinKit.swift")
            ])
        ], swiftLanguageModes: [.v5])
  SWIFT
  command = ['swift', 'run', '--package-path', directory]
  scratch = ENV['VQMETRIX_CAPTURE_TEST_BUILD_PATH']
  command += ['--scratch-path', File.expand_path(scratch)] if scratch && !scratch.empty?
  abort 'Capture/package test failed; partial fixtures were retained for inspection.' unless system(*command, 'Probe', output)
end
puts "Verified five codec packages in #{output}"
