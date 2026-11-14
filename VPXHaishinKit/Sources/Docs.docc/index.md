# ``VPXHaishinKit``

Optional software VP8 and VP9 encoding and decoding for HaishinKit.

## Enable the provider

Add the `VPXHaishinKit` Swift Package product to your target, then register its
factory before starting streams or creating codec sessions:

```swift
import HaishinKit
import VPXHaishinKit

await VideoCodecFactory.shared.register(VPXVideoCodecFactory())
let settings = VideoCodecSettings(format: .vp9)
```

Importing the module does not register it. Until registration, the codec factory
supports only the built-in VideoToolbox H.264 and HEVC implementations. Repeated
registration of the same factory type has no effect. Registration affects newly
created sessions; an existing converter keeps its original implementation.

`VideoCodecFactory.supportedFormats(for:)` reports the implementations registered
for compression or decompression. The registry is independent of the transport
factories registered with `StreamSessionBuilderFactory`.

## Codec sessions

The existing media pipeline uses the codec factory when creating converters.
For standalone conversion, call `VideoCodecFactory.makeSession(mode:settings:inputFormat:)`
and pass a continuation to `VideoCodecSession.convert(_:continuation:)`. Calls to
an individual session must be serialized. Invalidate the session when finished.
Decompression selects its codec from the input `CMFormatDescription`, independently
of the default H.264 encoding settings.

Encoding requires iOS 16, tvOS 16, or Mac Catalyst 16 (macOS and visionOS follow
the core package minimums). Decoding also works on iOS/tvOS/Mac Catalyst 15.
The provider reports only the directions available on the running OS.

The provider encodes 8-bit SDR video from NV12 (video/full range), planar I420
(video/full range), BGRA, or ARGB input. VideoToolbox pixel transfer normalizes and
scales the image; libvpx performs the compression. Encoded sizes must be positive
even dimensions. Decoding produces 8-bit 4:2:0 NV12 pixel buffers and preserves the
input timestamps and durations. VP9 high-bit-depth and 4:4:4 video are unsupported.

Encoding uses realtime, zero-lookahead operation with no frame reordering.
`videoSize`, `bitRate`, `expectedFrameRate`, `maxKeyFrameIntervalDuration`,
`scalingMode`, and the average/constant bitrate modes are supported. Constant mode
requires the same OS versions as `VideoCodecSettings.BitRateMode.constant`.
Variable bitrate mode is rejected. H.264/HEVC profile settings, hardware encoder
selection, and VideoToolbox-specific data-rate limits do not configure libvpx. Keyframes are
scheduled from media timestamps so dropped frames do not extend their interval.

## Transport support

Codec registration does not add RTP packetizers or Enhanced RTMP/TS framing.
RTC, RTMP, and SRT retain their existing video format restrictions and reject
VP8/VP9 encoding settings in this version. Transport support must be implemented
separately before publishing or playing these formats over those protocols.

## Dependency and distribution

Only the `VPXHaishinKit` product links libvpx; the core `HaishinKit` target does not
depend on it. The Swift package dependency is libvpx-xcframework 1.17.0 or later in
the compatible major version. Its current artifact contains arm64 slices for iOS,
macOS, Mac Catalyst, tvOS, and visionOS, including Apple silicon simulators.
Intel builds are not supported by that artifact.

Preserve libvpx's BSD license and patent notice in your app's third-party notices.
SwiftPM does not automatically include the XCFramework's top-level `Licenses/`
directory in the final app. See the libvpx-xcframework distribution documentation.
