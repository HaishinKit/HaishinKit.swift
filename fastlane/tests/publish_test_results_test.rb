require 'fastlane'
require 'minitest/autorun'
require 'tmpdir'
require_relative '../actions/publish_test_results'

class PublishTestResultsTest < Minitest::Test
  Reporter = Fastlane::Actions::PublishTestResultsAction

  def setup
    @directory = Dir.mktmpdir
    @summary = File.join(@directory, 'summary.md')
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def write(name, contents)
    File.write(File.join(@directory, name), contents)
  end

  def run_action(outcome: 'success')
    params = FastlaneCore::Configuration.create(Reporter.available_options,
                                               directory: @directory, outcome: outcome, summary: @summary)
    Reporter.run(params)
  end

  def test_combines_xctest_and_swift_testing
    write('tests.xml', '<testsuite><testcase classname="XCTest" name="one" /></testsuite>')
    write('tests-swift-testing.xml', <<~XML)
      <testsuites><testsuite>
        <testcase classname="SwiftTests" name="two" />
        <testcase classname="SwiftTests" name="three"><skipped /></testcase>
      </testsuite></testsuites>
    XML
    output, = capture_io { assert run_action }
    assert_empty output
    summary = File.read(@summary)
    assert_includes summary, '3 tests · 2 passed · 0 failed · 1 skipped'
    assert_includes summary, 'XCTest'
    assert_includes summary, 'SwiftTests'
  end

  def test_failure_messages_are_visible_and_escaped
    write('tests-swift-testing.xml', <<~XML)
      <testsuites><testsuite>
        <testcase classname="SRTTests" name="int64()">
          <failure message="Invalid socket ID &lt;script&gt;">&lt;b&gt;details&lt;/b&gt;</failure>
        </testcase>
        <testcase classname="SRTTests" name="other"><error message="runner error" /></testcase>
      </testsuite></testsuites>
    XML
    output, = capture_io { assert_raises(FastlaneCore::Interface::FastlaneTestFailure) { run_action(outcome: 'failure') } }
    assert_equal 2, output.lines.grep(/^::error /).length
    assert_includes output, '::error title=SRTTests.int64()::Invalid socket ID'
    assert_includes output, '%0A<b>details</b>'
    summary = File.read(@summary)
    assert_includes summary, '2 failed'
    assert_includes summary, 'Invalid socket ID &lt;script&gt;'
    assert_includes summary, '&lt;b&gt;details&lt;/b&gt;'
    refute_includes summary, '<script>'
  end

  def test_swift_testing_failure_resolves_source_and_deduplicates_fastlane_output
    log = "[05:12:10]: ▸ \e[35m✘ Test int64() recorded an issue at SRTSocketOptionTests.swift:45:6: Caught error: .invalidOption(\"Invalid socket ID\")\e[0m\n"
    test = { suite: 'SRTTests', name: 'int64()', status: 'Failed', details: 'Caught error: .invalidOption("Invalid socket ID")' }
    commands = Reporter.annotations([test], log + log, ['SRTHaishinKit/Tests/SRT/SRTSocketOptionTests.swift'], '/repo')
    assert_equal [
      '::error title=int64(),file=SRTHaishinKit/Tests/SRT/SRTSocketOptionTests.swift,line=45,col=6::SRTSocketOptionTests.swift:45:6: Caught error: .invalidOption("Invalid socket ID")'
    ], commands
  end

  def test_located_annotation_retains_issue_comment_from_xml
    write('tests-swift-testing.xml', <<~XML)
      <testsuites><testsuite>
        <testcase classname="HaishinKitTests.CIAnnotationSmokeTests" name="intentionalFailureForAnnotationValidation()">
          <failure message="Issue recorded (error): Intentional failure to verify GitHub Actions annotations (temporary)." />
        </testcase>
      </testsuite></testsuites>
    XML
    log = <<~LOG
      [06:14:43]: ▸ ✘ Test intentionalFailureForAnnotationValidation() recorded an issue at CIAnnotationSmokeTests.swift:5:21: Issue recorded
      [06:14:43]: ▸ ↳ Intentional failure to verify GitHub Actions annotations (temporary).
    LOG
    cases, = Reporter.load_results(@directory)
    command, = Reporter.annotations(cases, log, ['HaishinKit/Tests/Util/CIAnnotationSmokeTests.swift'], '/repo')
    assert_includes command, ',file=HaishinKit/Tests/Util/CIAnnotationSmokeTests.swift,line=5,col=21::'
    assert_includes command, 'Issue recorded (error): Intentional failure to verify GitHub Actions annotations (temporary).'
  end

  def test_does_not_mix_xml_details_from_tests_with_the_same_name
    cases = [
      { suite: 'One', name: 'example()', status: 'Failed', details: 'first failure' },
      { suite: 'Two', name: 'example()', status: 'Failed', details: 'second failure' }
    ]
    log = '✘ Test example() recorded an issue at Tests.swift:2:3: original failure'
    command, = Reporter.annotations(cases, log, ['One/Tests.swift'], '/repo')
    assert_includes command, 'original failure'
    refute_includes command, 'first failure'
    refute_includes command, 'second failure'
  end

  def test_source_resolution_does_not_guess_ambiguous_or_external_paths
    sources = ['One/Tests.swift', 'Two/Tests.swift']
    {
      'Tests.swift' => nil,
      'Missing.swift' => nil,
      '/other/One/Tests.swift' => nil,
      'One/Tests.swift' => 'One/Tests.swift',
      '/repo/One/Tests.swift' => 'One/Tests.swift'
    }.each do |filename, expected|
      log = "✘ Test example() recorded an issue at #{filename}:2:3: failed"
      command = Reporter.annotations([], log, sources, '/repo').first
      if expected
        assert_includes command, ",file=#{expected},line=2,col=3::"
      else
        refute_includes command, ',file='
      end
      assert_includes command, "#{filename}:2:3: failed"
    end
  end

  def test_known_issues_and_passing_tests_are_not_errors
    log = <<~LOG
      ✘ Test expectedFailure() recorded a known issue at Tests.swift:3:4: expected
      ✔ Test success() passed after 0.001 seconds.
    LOG
    assert_empty Reporter.annotations([], log, ['Tests.swift'], '/repo')
  end

  def test_annotation_values_cannot_inject_workflow_commands_or_properties
    command = Reporter.annotation("test(x:,y:)\n100%", "failure\r\n::warning::injected%0A", file: 'Tests,x:.swift')
    assert_equal '::error title=test(x%3A%2Cy%3A)%0A100%25,file=Tests%2Cx%3A.swift::failure%0D%0A::warning::injected%250A', command
  end

  def test_missing_results_are_not_success
    output, = capture_io { assert_raises(FastlaneCore::Interface::FastlaneTestFailure) { run_action } }
    assert_includes output, 'No test cases were reported'
    assert_includes File.read(@summary), 'Failed / incomplete'
  end

  def test_failed_command_with_partial_results_is_not_success
    write('tests.xml', '<testsuite><testcase name="one" /></testsuite>')
    output, = capture_io { assert_raises(FastlaneCore::Interface::FastlaneTestFailure) { run_action(outcome: 'failure') } }
    assert_includes output, '::error title=Review failed::'
    assert_includes File.read(@summary), 'results may be incomplete'
  end

  def test_log_errors_with_incomplete_xml_are_not_success
    write('tests.xml', '<testsuite><testcase name="one" /></testsuite>')
    write('review.log', '✘ Test two() recorded an issue at Tests.swift:1:2: failed')
    capture_io { assert_raises(FastlaneCore::Interface::FastlaneTestFailure) { run_action } }
    assert_includes File.read(@summary), 'Failed / incomplete'
  end

  def test_malformed_xml_still_produces_summary_and_annotations
    write('tests.xml', '<testsuites>')
    output, = capture_io { assert_raises(FastlaneCore::Interface::FastlaneTestFailure) { run_action(outcome: 'failure') } }
    assert_includes output, '::error title=Test results unavailable::Cannot read tests.xml'
    assert_includes File.read(@summary), 'Failed / incomplete'
  end

  def test_limits_annotations_and_retains_failure_details_in_summary
    cases = 11.times.map { |index| "<testcase name=\"test#{index}\"><failure message=\"failure#{index}\" /></testcase>" }.join
    write('tests-swift-testing.xml', "<testsuite>#{cases}</testsuite>")
    output, = capture_io { assert_raises(FastlaneCore::Interface::FastlaneTestFailure) { run_action(outcome: 'failure') } }
    assert_equal 10, output.lines.grep(/^::error /).length
    assert_includes File.read(@summary), 'Only the first 10 errors'
    assert_includes File.read(@summary), 'failure10'
  end

  def test_rejects_invalid_outcome
    assert_raises(FastlaneCore::Interface::FastlaneError) { run_action(outcome: 'unknown') }
  end
end
