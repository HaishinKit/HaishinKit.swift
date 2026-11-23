require 'open3'
require 'rexml/document'
require 'base64'

module MacOSUpdateFeed
  NAMESPACE = 'http://www.andymatuschak.org/xml-namespaces/sparkle'

  def self.validate(path, archive:, version:, url:)
    document = REXML::Document.new(File.read(path))
    items = REXML::XPath.match(document, '/rss/channel/item')
    raise 'Expected one update item' unless items.length == 1
    item = items.first
    actual_version = REXML::XPath.first(item, 'sparkle:version', 'sparkle' => NAMESPACE)&.text
    raise 'Incorrect update version' unless actual_version == version
    enclosure = item.elements['enclosure']
    raise 'Incorrect update URL' unless enclosure&.attributes&.[]('url') == url
    raise 'Incorrect archive length' unless enclosure.attributes['length'] == File.size(archive).to_s
    signature = enclosure.attributes['sparkle:edSignature']
    raise 'Missing archive signature (check that the secret matches SUPublicEDKey)' unless signature && Base64.strict_decode64(signature).bytesize == 64
    minimum = REXML::XPath.first(item, 'sparkle:minimumSystemVersion', 'sparkle' => NAMESPACE)&.text
    raise 'Missing minimum OS' if minimum.to_s.empty?
    document
  end

  def self.generate(tool_dir:, directory:, archive:, version:, private_key:)
    raise 'SPARKLE_ED_PRIVATE_KEY is required' if private_key.to_s.strip.empty?
    prefix = "https://github.com/HaishinKit/HaishinKit.swift/releases/download/#{version}/"
    feed = File.join(directory, 'appcast.xml')
    # Pass the secret via standard input, never as a command-line argument or log entry.
    output, status = Open3.capture2e(File.join(tool_dir, 'generate_appcast'), '--ed-key-file', '-',
      '--download-url-prefix', prefix, '--link', "https://github.com/HaishinKit/HaishinKit.swift/releases/tag/#{version}",
      '--maximum-deltas', '0', '-o', feed, directory, stdin_data: private_key)
    raise 'Sparkle could not generate a signed update feed' unless status.success?
    validate(feed, archive: archive, version: version, url: prefix + File.basename(archive))
    # This also rejects an unsigned feed even if archive signing succeeded.
    _output, status = Open3.capture2e(File.join(tool_dir, 'sign_update'), '--verify', '--ed-key-file', '-', feed, stdin_data: private_key)
    raise 'Sparkle feed signature verification failed' unless status.success?
    feed
  end
end
