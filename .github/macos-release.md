# macOS example releases

Pushing a release tag such as `2.2.0` runs the Release workflow and attaches
`HaishinKit-macOS-<version>-arm64-adhoc.zip` to the matching GitHub Release.
If the release does not exist, the workflow creates a draft for review and manual
publication. Existing release notes are preserved. Rerunning replaces the ZIP
for that version.

To add the app to an existing release, run the Release workflow manually with
its exact tag as `version`. The selected workflow revision must contain this
workflow, and the tag must contain the updated `macos_example` lane that signs
and verifies `arm64-adhoc.zip`, plus the example workspace. Tags with only the
older unsigned lane cannot produce an ad-hoc archive through this workflow;
use that tag's workflow revision if you need its legacy unsigned package.
The workflow checks for the ad-hoc archive before creating or updating a
GitHub Release. Documentation publication runs independently in the same workflow.

The app supports Apple Silicon Macs with macOS 15.5 or later.
It is ad-hoc signed, without Developer ID signing or notarization. macOS Gatekeeper may block the downloaded
app. Only open a download you trust; if macOS permits an exception, use
System Settings → Privacy & Security → Open Anyway after attempting to open it.
Managed Macs may prohibit exceptions.

Before creating the ZIP, Fastlane signs nested frameworks and Sparkle helpers
inside-out, preserves their individual entitlements, signs the sandboxed app, and
verifies the complete bundle. It then extracts the ZIP into a temporary directory
and verifies the distributed app again. A signing or verification failure stops
the workflow before upload. No Apple certificate is needed for ad-hoc signing.

To build locally with Xcode and the repository's Ruby/Bundler dependencies:

```sh
bundle exec fastlane macos_example version:2.2.0
```

The ZIP is written to `build/macos-example/2.2.0/`. Open
`Examples/Examples.xcworkspace` to build the sample together with the local
library in Xcode. No Apple signing secrets are required for this workflow.

## Automatic updates

The macOS sample uses Sparkle 2.10.1. The app menu offers **Check for Updates…**;
**Settings → App updates** controls automatic checks and automatic installation.
Automatic checks are enabled initially; automatic download/installation is an
explicit user choice. Published stable releases supply the signed `appcast.xml`
at `https://github.com/HaishinKit/HaishinKit.swift/releases/latest/download/appcast.xml`.
Both the feed and the update ZIP are Ed25519-signed; the app verifies the update
before extracting it. Developer ID signing/notarization remains separate.

The first version containing the updater must be installed manually. Earlier
versions have no updater. Draft releases and prereleases are not the stable
update channel. A release must be published with both its ZIP and `appcast.xml`
to become available. Never replace an archive without regenerating its feed.

`SPARKLE_ED_PRIVATE_KEY` is a repository Actions Secret used only by the release
build step. Its matching public key is `SUPublicEDKey` in the app's Info.plist.
The release lane fails before building a stable update if this secret is missing,
and rejects feeds without the expected signed ZIP, version, length and URL.
The app's bundle version follows the stable release version so later releases
compare correctly. Do not rotate or discard the signing key casually: ad-hoc
signed apps cannot rely on Developer ID to authorize key rotation.

The dedicated local key is stored in Keychain under Sparkle's service
`https://sparkle-project.org`, account `com.haishinkit.macos`. Export a secure
backup using Sparkle's `generate_keys --account com.haishinkit.macos -x <file>`;
never commit or log that file. A GitHub Secret cannot be downloaded as a backup.

Release CI runs `fastlane macos_example version:<version> updates:true`.
Local `macos_example` builds omit the feed by default; creating one explicitly
requires the same private key. Do not publish validation/test feeds as real updates.

## Licenses in the app

**Configuration → Licenses** lists runtime dependencies and their bundled
license, patent and source-availability notices. License text is generated from
the resolved source packages and XCFramework distributions on every app build,
including libdatachannel's bundled components. Build-only documentation tools
are excluded. Missing notices stop the build rather than silently disappearing.
For a custom SwiftPM cache, set `HAISHINKIT_SOURCE_PACKAGES_DIR` to its directory.
The build phase keeps Xcode's script sandbox enabled.
