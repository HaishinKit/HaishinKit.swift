require 'cgi'
require 'open3'
require 'rexml/document'

module Fastlane
  module Actions
    class PublishTestResultsAction < Action
      ANSI = /\e\[[0-?]*[ -\/]*[@-~]/
      ISSUE = /✘ Test (.*?) recorded an issue at (.*?):(\d+):(\d+): (.*)/

      def self.run(params)
        repository = File.expand_path('../..', __dir__)
        directory = File.expand_path(params[:directory], repository)
        cases, problems = load_results(directory)
        files, status = Open3.capture2('git', 'ls-files', '-z', '--', '*.swift', chdir: repository)
        UI.user_error!('Cannot list source files for test annotations') unless status.success?
        log_path = File.join(directory, 'review.log')
        log = File.exist?(log_path) ? File.read(log_path, encoding: 'UTF-8').scrub : ''
        commands = annotations(cases, log, files.split("\0"), repository)
        commands.concat(problems.map { |problem| annotation('Test results unavailable', problem) })
        if params[:outcome] != 'success' && commands.empty?
          commands << annotation('Review failed', 'See review.log for build or runner errors; test results may be incomplete.')
        end
        summary, failed = render(cases, problems, params[:outcome], has_errors: !commands.empty?)
        # Actions accepts at most 10 error annotations per step.
        if commands.length > 10
          summary << "\nOnly the first 10 errors are annotated. See test-logs for all failure details.\n"
        end
        # Bypass fastlane's timestamp/color prefix so the runner sees workflow commands.
        commands.first(10).each { |command| $stdout.puts(command) }
        File.open(params[:summary], 'a:UTF-8') { |file| file.write(summary) } if params[:summary]
        UI.test_failure!('Tests failed or results are incomplete. See the test summary and test-logs artifact.') if failed
        true
      end

      def self.load_results(directory)
        cases = []
        problems = []
        # SwiftPM adds '-swift-testing' to the requested filename for Swift Testing.
        Dir.glob(File.join(directory, '*.xml')).sort.each do |path|
          begin
            document = REXML::Document.new(File.read(path))
            document.elements.each('//testcase') do |test|
              issues = test.get_elements('failure') + test.get_elements('error')
              status = if !issues.empty?
                         'Failed'
                       elsif test.elements['skipped']
                         'Skipped'
                       else
                         'Passed'
                       end
              cases << {
                suite: test.attributes['classname'] || File.basename(path, '.xml'),
                name: test.attributes['name'] || 'Unnamed test',
                status: status,
                details: issues.map do |issue|
                  [issue.attributes['message'], issue.texts.map(&:value).join].compact.reject(&:empty?).join("\n")
                end.join("\n")
              }
            end
          rescue REXML::ParseException, SystemCallError => error
            problems << "Cannot read #{File.basename(path)}: #{error.message}"
          end
        end
        if cases.empty?
          problems << 'No test cases were reported. The build or test runner may have failed before producing results. See review.log.'
        end
        [cases, problems]
      end

      def self.annotations(cases, log, sources, repository)
        reported = []
        # Swift Testing's XML omits source locations; its console diagnostics include them.
        # fastlane may repeat the command output on failure, so deduplicate diagnostics.
        commands = log.gsub(ANSI, '').scan(ISSUE).uniq.map do |name, filename, line, column, message|
          reported << name
          # XML retains issue comments that the console prints on subsequent lines.
          matches = cases.select { |test| test[:status] == 'Failed' && test[:name] == name }
          message = matches.first[:details] if matches.one? && !matches.first[:details].empty?
          path = filename.delete_prefix("#{repository}/")
          candidates = sources.select { |source| source == path || source.end_with?("/#{path}") }
          location = candidates.one? ? { file: candidates.first, line: line, col: column } : {}
          # Preserve the original location in the message even when the path is ambiguous.
          annotation(name, "#{filename}:#{line}:#{column}: #{message}", **location)
        end
        cases.each do |test|
          next unless test[:status] == 'Failed' && !reported.include?(test[:name])

          commands << annotation("#{test[:suite]}.#{test[:name]}", test[:details])
        end
        commands
      end

      def self.annotation(title, message, **location)
        properties = { title: title, **location }.map do |key, value|
          "#{key}=#{workflow_escape(value.to_s).gsub(':', '%3A').gsub(',', '%2C')}"
        end
        "::error #{properties.join(',')}::#{workflow_escape(message)}"
      end

      def self.workflow_escape(value)
        value.gsub('%', '%25').gsub("\r", '%0D').gsub("\n", '%0A')
      end

      def self.render(cases, problems, outcome, has_errors: false)
        counts = Hash.new(0).merge(cases.map { |test| test[:status] }.tally)
        failed = outcome != 'success' || counts['Failed'].positive? || !problems.empty? || has_errors
        status = failed ? 'Failed / incomplete' : 'Passed'
        totals = "#{cases.length} tests · #{counts['Passed']} passed · #{counts['Failed']} failed · #{counts['Skipped']} skipped"
        summary = ['## Test results', '', "**#{status}** — #{totals}", '']
        notices = problems.dup
        if outcome != 'success'
          notices << 'The review command did not succeed. These results may be incomplete; see review.log for build or runner errors.'
        end
        notices.each { |notice| summary.concat([CGI.escapeHTML(notice), '']) }
        failures = cases.select { |test| test[:status] == 'Failed' }
        unless failures.empty?
          summary.concat(['### Failures', ''])
          # Bound the summary; the XML artifact retains the complete details.
          failures.first(20).each do |test|
            name = CGI.escapeHTML("#{test[:suite]}.#{test[:name]}")
            details = CGI.escapeHTML(test[:details][0, 2000])
            summary.concat(["<details><summary>#{name}</summary>", '', "<pre>#{details}</pre>", '', '</details>', ''])
          end
          summary.concat(['More failures are listed in the test-logs artifact.', '']) if failures.length > 20
        end
        summary.concat(['| Suite | Passed | Failed | Skipped |', '| --- | ---: | ---: | ---: |'])
        cases.group_by { |test| test[:suite] }.sort.each do |suite, tests|
          counts = Hash.new(0).merge(tests.map { |test| test[:status] }.tally)
          name = CGI.escapeHTML(suite).gsub('|', '&#124;').gsub("\n", ' ')
          summary << "| #{name} | #{counts['Passed']} | #{counts['Failed']} | #{counts['Skipped']} |"
        end
        [summary.join("\n") + "\n", failed]
      end

      def self.description
        'Annotate SwiftPM test failures and summarize results in GitHub Actions'
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(key: :directory, description: 'Results directory relative to the repository root',
                                      type: String, default_value: 'test-results'),
          FastlaneCore::ConfigItem.new(key: :outcome, description: 'Outcome of the review step', type: String,
                                      verify_block: proc do |value|
                                        UI.user_error!('Outcome must be success, failure, or cancelled') unless %w[success failure cancelled].include?(value)
                                      end),
          FastlaneCore::ConfigItem.new(key: :summary, description: 'GitHub Actions job summary path', type: String,
                                      env_name: 'GITHUB_STEP_SUMMARY', optional: true)
        ]
      end

      def self.is_supported?(_platform)
        true
      end
    end
  end
end
