# GitHub Actions conventions

- Use Ruby and its standard library for helper scripts in GitHub Actions and Fastlane. Do not introduce Python for workflow helpers.
- Use shell for simple command execution. Prefer existing Fastlane lanes for shared build and release logic.
- Failure-reporting helpers must work even when dependency installation or `ruby/setup-ruby` fails: use runner-provided Ruby without Bundler or additional gems.
- If Ruby cannot reasonably satisfy a requirement, explain the constraint before introducing another scripting language.
