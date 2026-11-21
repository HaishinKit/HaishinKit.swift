# GitHub Actions conventions

- Use Ruby and its standard library for helper scripts in GitHub Actions and Fastlane. Do not introduce Python for workflow helpers.
- Use shell for simple command execution. Prefer existing Fastlane lanes for shared build and release logic.
- Failure-reporting helpers must work even when dependency installation or `ruby/setup-ruby` fails: use runner-provided Ruby without Bundler or additional gems.
- If Ruby cannot reasonably satisfy a requirement, explain the constraint before introducing another scripting language.

# Example applications

- Do not add or reintroduce VoiceOver-specific actions for adding, selecting, or editing ScreenObjects in the example apps. Keep accessibility labels on standard controls.

# README conventions

- Write README files for people: keep them concise, easy to scan, and focused on the library overview, installation, API documentation links, and examples.
- Use an emoji in the README title and section headings. Keep wording short and preserve the document's language.
- Place relevant, accurate build, package-distribution, platform, and license badges near the README title.
- Describe only library capabilities under Features. Introduce sample applications, their UI, screenshots, and sample-specific requirements in a separate Examples section.
- Include a minimal, usable installation example for the actual distribution channel, such as SwiftPM, JitPack, or pub.dev. Clearly distinguish development references from published release tags.
- Keep detailed API usage, lifecycle, authentication, and integration guides in the generated reference: DocC for Swift, Dokka for Kotlin/Android, and dartdoc for Dart/Flutter. Link to those references from README instead of duplicating long guides.
- Check existing README statements against the current implementation and build configuration. Update or remove obsolete version assumptions, unsupported claims, and stale instructions when editing the document.
- Prefer representative screenshots of actual example applications, labeled accurately. Keep sample UI details out of the library feature list.
- Apply this same policy across KaiwaKit and the HaishinKit Swift, Kotlin, and Dart repositories.
