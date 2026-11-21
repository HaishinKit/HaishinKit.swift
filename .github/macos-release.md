# macOS example releases

Pushing a release tag such as `2.2.0` runs the Release workflow and attaches
`HaishinKit-macOS-<version>-arm64-unsigned.zip` to the matching GitHub Release.
If the release does not exist, the workflow creates a draft for review and manual
publication. Existing release notes are preserved. Rerunning replaces the ZIP
for that version.

To add the app to an existing release, run the Release workflow manually with
its exact tag as `version`. The selected workflow revision must contain this
workflow, and the tag must contain the `macos_example` Fastlane lane and the
example workspace. Documentation publication runs independently in the same
workflow.

The app supports Apple Silicon Macs with macOS 15.5 or later.
It is unsigned and not notarized. macOS Gatekeeper may block the downloaded
app. Only open a download you trust; if macOS permits an exception, use
System Settings → Privacy & Security → Open Anyway after attempting to open it.
Managed Macs may prohibit exceptions.

To build locally with Xcode and the repository's Ruby/Bundler dependencies:

```sh
bundle exec fastlane macos_example version:2.2.0
```

The ZIP is written to `build/macos-example/2.2.0/`. Open
`Examples/Examples.xcworkspace` to build the sample together with the local
library in Xcode. No Apple signing secrets are required for this workflow.
