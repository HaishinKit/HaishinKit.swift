# Generates the notices from the exact resolved packages and binary distributions.
require 'json'
require 'fileutils'

root, packages, output = ARGV
abort 'Usage: generate-macos-licenses.rb ROOT SOURCE_PACKAGES OUTPUT' unless output
state = JSON.parse(File.read(File.join(packages, 'workspace-state.json'))).fetch('object')
versions = state.fetch('dependencies').map do |dependency|
  version = dependency.dig('state', 'checkoutState', 'version')
  [dependency.fetch('packageRef').fetch('identity'), version] if version
end.to_h
read = ->(path) { text = File.read(path, encoding: 'UTF-8'); abort "Empty license: #{path}" if text.strip.empty?; text }
checkout = ->(name, file) { File.join(packages, 'checkouts', name, file) }
artifact = ->(name, product, file) { File.join(packages, 'artifacts', name, product, "#{product}.xcframework", 'Licenses', file) }
entries = []
add = lambda do |name, identity, url, paths|
  entries << { name: name, version: identity ? versions.fetch(identity) : ENV.fetch('MARKETING_VERSION', 'Development'), url: url,
               text: paths.map { |path| "#{File.basename(path)}\n\n#{read.call(path)}" }.join("\n\n————————————————————————\n\n") }
end
add.call('HaishinKit', nil, 'https://github.com/HaishinKit/HaishinKit.swift', [File.join(root, 'LICENSE.md')])
add.call('Logboard', 'logboard', 'https://github.com/shogo4405/Logboard', [checkout.call('Logboard', 'LICENSE.md')])
add.call('Sparkle', 'sparkle', 'https://github.com/sparkle-project/Sparkle', [File.join(packages, 'artifacts/sparkle/Sparkle/LICENSE')])
add.call('libdatachannel', 'libdatachannel-xcframework', 'https://github.com/HaishinKit/libdatachannel-xcframework', %w[THIRD-PARTY-LICENSES.txt SOURCE-NOTICE.txt SOURCES.json].map { |file| artifact.call('libdatachannel-xcframework', 'libdatachannel', file) })
add.call('SRT', 'libsrt-xcframework', 'https://github.com/HaishinKit/libsrt-xcframework', %w[THIRD-PARTY-LICENSES.txt SOURCE-NOTICE.txt SOURCES.json].map { |file| artifact.call('libsrt-xcframework', 'libsrt', file) })
{'libaom' => %w[LICENSE PATENTS AUTHORS vector-LICENSE fastfeat-LICENSE SOURCES.json], 'libvpx' => %w[LICENSE PATENTS AUTHORS SOURCES.json]}.each do |name, files|
  add.call(name, "#{name}-xcframework", "https://github.com/HaishinKit/#{name}-xcframework", [checkout.call("#{name}-xcframework", 'LICENSE.md')] + files.map { |file| artifact.call("#{name}-xcframework", name, file) })
end
add.call('OpenSSL', 'openssl-package', 'https://github.com/krzyzanowskim/OpenSSL-Package', [checkout.call('OpenSSL-Package', 'LICENSE')])
header = read.call(File.join(packages, 'artifacts/openssl-package/OpenSSL/OpenSSL.xcframework/macos-arm64_x86_64/OpenSSL.framework/Headers/opensslv.h'))
entries.last[:text] = "#{header[/\/\*.*?\*\//m]}\n\n#{entries.last[:text]}"
FileUtils.mkdir_p(File.dirname(output))
File.write(output, JSON.pretty_generate(entries) + "\n")
puts "Bundled license notices for #{entries.length} components."
