require 'cgi'
require 'open3'

module Fastlane
  module Actions
    class PublishDocumentationResultsAction < Action
      ANSI = /\e\[[0-?]*[ -\/]*[@-~]/

      def self.run(params)
        repository = File.expand_path('../..', __dir__)
        path = File.expand_path(params[:log], repository)
        log = File.exist?(path) ? File.read(path, encoding: 'UTF-8').scrub : ''
        files, status = Open3.capture2('git', 'ls-files', '-z', chdir: repository)
        UI.user_error!('Cannot list source files for documentation annotations') unless status.success?
        errors = diagnostics(log, files.split("\0"), repository)
        if log.strip.empty?
          errors << { message: 'Documentation log is missing or empty. See the document step for details.' }
        elsif params[:outcome] != 'success' && errors.empty?
          tail = clean(log).lines.last(20).join[0, 3000]
          errors << { message: "The document lane failed. See documentation-logs/document.log.\n\n#{tail}" }
        end
        failed = params[:outcome] != 'success' || !errors.empty?
        # Print workflow commands directly, without fastlane's timestamp/color prefix.
        errors.first(10).each { |error| $stdout.puts(annotation(error)) }
        if params[:summary]
          File.open(params[:summary], 'a:UTF-8') { |file| file.write(render(errors, failed)) }
        end
        UI.user_error!('Documentation failed. See annotations and the documentation-logs artifact.') if failed
        true
      end

      def self.clean(log)
        log.gsub(ANSI, '').lines.map do |line|
          line.sub(/^\d{4}-\d\d-\d\dT\S+\s+/, '').sub(/^\[\d\d:\d\d:\d\d\]:\s*/, '').sub(/^▸\s*/, '').strip
        end.join("\n")
      end

      def self.diagnostics(log, sources, repository)
        # SwiftPM wraps symbolgraph-extract stderr in a quoted error with literal \n.
        # Unwrap it so the actual compiler error is visible instead of a huge command.
        lines = clean(log).lines.flat_map do |line|
          if line.include?('output:\\n')
            line.split('output:\\n', 2).last.gsub('\\n', "\n").gsub("\\'", "'").sub(/"\)\s*\z/, '').lines
          else
            [line]
          end
        end
        lines.filter_map do |line|
          line = line.strip
          located = line.match(/\A(.+?):(\d+)(?::(\d+))?:\s*(?:fatal )?error:\s*(.+)\z/i)
          if located
            filename, row, column, message = located.captures
            path = filename.delete_prefix("#{repository}/")
            candidates = sources.select { |source| source == path || source.end_with?("/#{path}") }
            location = if candidates.one? && row.to_i.positive?
                         { file: candidates.first, line: row }.tap { |value| value[:col] = column if column }
                       else
                         {}
                       end
            { message: "#{filename}:#{row}#{column ? ":#{column}" : ''}: #{message}", **location }
          elsif (match = line.match(/\A(?:fatal error|error|fatal):\s*(.+)\z/i))
            { message: match[1] }
          end
        end.uniq
      end

      def self.escape(value)
        value.to_s.gsub('%', '%25').gsub("\r", '%0D').gsub("\n", '%0A')
      end

      def self.annotation(error)
        properties = { title: 'Documentation failed', **error.reject { |key, _| key == :message } }
                     .map { |key, value| "#{key}=#{escape(value).gsub(':', '%3A').gsub(',', '%2C')}" }
        "::error #{properties.join(',')}::#{escape(error[:message][0, 4000])}"
      end

      def self.render(errors, failed)
        summary = ['## Documentation', '', "**#{failed ? 'Failed / incomplete' : 'Passed'}**", '',
                   'Full log: `documentation-logs` artifact → `document.log`.', '']
        errors.first(20).each { |error| summary.concat(["<pre>#{CGI.escapeHTML(error[:message][0, 4000])}</pre>", '']) }
        summary << 'Only the first 10 errors are annotated. See the full log for all diagnostics.' if errors.length > 10
        summary.join("\n") + "\n"
      end

      def self.description
        'Annotate documentation failures and summarize results in GitHub Actions'
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(key: :log, description: 'Log path relative to the repository root',
                                      type: String, default_value: 'documentation-results/document.log'),
          FastlaneCore::ConfigItem.new(key: :outcome, description: 'Outcome of the document step', type: String,
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
