require 'fastlane'
require 'minitest/autorun'
require 'tmpdir'
require_relative '../actions/publish_documentation_results'

class PublishDocumentationResultsTest < Minitest::Test
  Reporter = Fastlane::Actions::PublishDocumentationResultsAction

  def setup
    @directory = Dir.mktmpdir
    @log = File.join(@directory, 'document.log')
    @summary = File.join(@directory, 'summary.md')
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def run_action(outcome: 'failure')
    params = FastlaneCore::Configuration.create(Reporter.available_options,
                                               log: @log, outcome: outcome, summary: @summary)
    Reporter.run(params)
  end

  def test_extracts_actual_symbolgraph_error_and_deduplicates_fastlane_replay
    log = %q{error: unspecified("terminated(1): /usr/bin/swift-symbolgraph-extract -module-name RTC output:\n    <unknown>:0: error: missing required module \'OpenSSL\'\n    Error: Failed to load the module \'RTC\'. Are you missing build dependencies or include/framework directories?\n    See the previous error messages for details. Aborting.")}
    log = "2026-11-01T06:24:05.0766240Z [06:24:05]: ▸ \e[35m#{log}\e[0m\n"
    errors = Reporter.diagnostics(log + log, [], '/repo')
    assert_equal 2, errors.size
    assert_equal "<unknown>:0: missing required module 'OpenSSL'", errors.first[:message]
    assert_includes errors.last[:message], "Failed to load the module 'RTC'"
    refute errors.first.key?(:file)
    refute_includes Reporter.annotation(errors.first), 'swift-symbolgraph-extract'
  end

  def test_links_source_errors_and_docc_errors_without_columns
    log = "[06:24:05]: ▸ /repo/Sources/Stream.swift:12:4: error: cannot find type\nDocs.docc/Guide.md:7: error: broken documentation\n"
    errors = Reporter.diagnostics(log, ['Sources/Stream.swift', 'Docs.docc/Guide.md'], '/repo')
    assert_includes Reporter.annotation(errors.first), ',file=Sources/Stream.swift,line=12,col=4::'
    assert_includes Reporter.annotation(errors.last), ',file=Docs.docc/Guide.md,line=7::'
  end

  def test_does_not_guess_ambiguous_or_external_source_locations
    sources = ['One/File.swift', 'Two/File.swift']
    %w[File.swift /external/One/File.swift].each do |path|
      errors = Reporter.diagnostics("#{path}:1:2: error: failed", sources, '/repo')
      refute errors.first.key?(:file)
      assert_includes errors.first[:message], path
    end
  end

  def test_git_errors_are_annotated
    errors = Reporter.diagnostics('fatal: Could not read from remote repository.', [], '/repo')
    assert_equal 'Could not read from remote repository.', errors.first[:message]
  end

  def test_success_and_warnings_do_not_produce_error_annotations
    File.write(@log, "warning: unresolved reference\nDocumentation generated\n")
    output, = capture_io { assert run_action(outcome: 'success') }
    assert_empty output
    assert_includes File.read(@summary), '**Passed**'
  end

  def test_failed_command_without_diagnostics_uses_log_tail
    File.write(@log, "Permission denied (publickey).\n")
    output, = capture_io { assert_raises(FastlaneCore::Interface::FastlaneError) { run_action } }
    assert_includes output, '::error title=Documentation failed::'
    assert_includes output, 'Permission denied (publickey).'
    assert_includes File.read(@summary), '**Failed / incomplete**'
  end

  def test_missing_log_is_not_success
    output, = capture_io { assert_raises(FastlaneCore::Interface::FastlaneError) { run_action(outcome: 'success') } }
    assert_includes output, 'Documentation log is missing or empty'
  end

  def test_diagnostics_fail_even_if_command_reports_success
    File.write(@log, "error: generation failed\n")
    capture_io { assert_raises(FastlaneCore::Interface::FastlaneError) { run_action(outcome: 'success') } }
  end

  def test_limits_annotations_and_escapes_summary
    File.write(@log, 11.times.map { |index| "error: failure#{index} <script>\n" }.join)
    output, = capture_io { assert_raises(FastlaneCore::Interface::FastlaneError) { run_action } }
    assert_equal 10, output.lines.grep(/^::error /).length
    summary = File.read(@summary)
    assert_includes summary, 'failure10 &lt;script&gt;'
    assert_includes summary, 'Only the first 10 errors'
    refute_includes summary, '<script>'
  end

  def test_escapes_workflow_commands_and_properties
    command = Reporter.annotation(message: "failure\r\n::warning::injected%0A", file: 'Docs,x:.md', line: 1)
    assert_equal '::error title=Documentation failed,file=Docs%2Cx%3A.md,line=1::failure%0D%0A::warning::injected%250A', command
  end

  def test_rejects_invalid_outcome
    assert_raises(FastlaneCore::Interface::FastlaneError) { run_action(outcome: 'unknown') }
  end
end
