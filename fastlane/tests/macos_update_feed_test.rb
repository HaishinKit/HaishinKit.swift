require 'minitest/autorun'
require 'tmpdir'
require_relative '../lib/macos_update_feed'

class MacOSUpdateFeedTest < Minitest::Test
  def setup
    @directory = Dir.mktmpdir
    @archive = File.join(@directory, 'HaishinKit.zip')
    File.write(@archive, 'archive fixture')
    @feed = File.join(@directory, 'appcast.xml')
    @url = 'https://github.com/HaishinKit/HaishinKit.swift/releases/download/2.3.2/HaishinKit.zip'
    @xml = <<~XML
      <rss xmlns:sparkle="#{MacOSUpdateFeed::NAMESPACE}"><channel><item>
        <sparkle:version>2.3.2</sparkle:version>
        <sparkle:minimumSystemVersion>15.5.0</sparkle:minimumSystemVersion>
        <enclosure url="#{@url}" length="#{File.size(@archive)}" sparkle:edSignature="#{Base64.strict_encode64('s' * 64)}" />
      </item></channel></rss>
    XML
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def validate(xml = @xml)
    File.write(@feed, xml)
    MacOSUpdateFeed.validate(@feed, archive: @archive, version: '2.3.2', url: @url)
  end

  def test_correct_archive_metadata
    assert_instance_of REXML::Document, validate
  end

  def test_unsigned_or_malformed_signatures_are_rejected
    assert_raises(RuntimeError) { validate(@xml.sub(/ sparkle:edSignature="[^"]+"/, '')) }
    assert_raises(RuntimeError) { validate(@xml.sub(Base64.strict_encode64('s' * 64), Base64.strict_encode64('short'))) }
  end

  def test_stale_version_or_different_archive_is_rejected
    assert_raises(RuntimeError) { validate(@xml.sub('<sparkle:version>2.3.2', '<sparkle:version>2.3.1')) }
    assert_raises(RuntimeError) { validate(@xml.sub('length="15"', 'length="99"')) }
    assert_raises(RuntimeError) { validate(@xml.sub(@url, 'https://example.com/other.zip')) }
  end

  def test_ambiguous_or_incomplete_feed_is_rejected
    assert_raises(RuntimeError) { validate(@xml.sub('</channel>', '<item /></channel>')) }
    assert_raises(RuntimeError) { validate(@xml.sub(/<sparkle:minimumSystemVersion>.*?<\/sparkle:minimumSystemVersion>/, '')) }
  end

  def test_missing_key_is_rejected_before_running_tools
    assert_raises(RuntimeError) { MacOSUpdateFeed.generate(tool_dir: 'missing', directory: @directory,
      archive: @archive, version: '2.3.2', private_key: '') }
  end
end
