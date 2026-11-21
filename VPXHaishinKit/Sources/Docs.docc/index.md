# ``VPXHaishinKit``

Standalone software VP8 and VP9 encoding and decoding for Apple platforms.

This optional product exposes ``VPXVideoEncoder``, ``VPXVideoDecoder``, and
``VPXVideoCodecSettings`` without depending on the `HaishinKit` target. Applications
such as VQMetrix can call it directly. The existing `VideoCodec`, codec registration,
MediaMixer, and RTC/RTMP/SRT pipelines are unchanged; importing this product does not
add VP8/VP9 transport support.

## Installation

This product is currently on the development PR branch, not in released 2.3.0:

```swift
.package(url: "https://github.com/HaishinKit/HaishinKit.swift.git",
         branch: "codex/optional-vpx-codecs")
```

Add `.product(name: "VPXHaishinKit", package: "HaishinKit.swift")` to your target.
After publication, replace the development branch with a release containing this product.

## Standalone conversion

The following function needs no `import HaishinKit` or shared codec registration:

```swift
import CoreMedia
import VPXHaishinKit

func roundTrip(_ references: [CMSampleBuffer]) throws -> [CMSampleBuffer] {
    let settings = VPXVideoCodecSettings(bitRate: 1_000_000, format: .vp9)
    let encoder = try VPXVideoEncoder(settings: settings)
    let decoder = try VPXVideoDecoder(format: .vp9)
    defer { encoder.invalidate(); decoder.invalidate() }
    var restored: [CMSampleBuffer] = []
    for reference in references {
        for packet in try encoder.encode(reference) {
            restored += try decoder.decode(packet)
        }
    }
    for packet in try encoder.finish() {
        restored += try decoder.decode(packet)
    }
    return restored
}
```

`encode` and `decode` synchronously return owned Core Media samples. Copying encoded
bytes and decoded pixels before libvpx reuses its buffers makes retained outputs safe.
The classes are deliberately non-Sendable: create and use each instance on one actor
or serial executor. Software compression runs on that caller; use a worker executor
for UI applications. The APIs throw errors directly rather than dropping outputs
through an asynchronous continuation.

## Settings and lifecycle

VP8 and VP9 use 8-bit SDR 4:2:0. The encoder accepts only video-range planar
I420 (`kCVPixelFormatType_420YpCbCr8Planar`), with dimensions exactly matching
`videoSize`. It passes the three planes and their row strides directly to libvpx
while the input pixel buffer is locked. The caller is responsible for color-space
conversion, range normalization, and resizing before encoding. NV12, RGB, full-range,
10-bit, and mismatched dimensions are rejected rather than converted implicitly.
Encoded width/height must be positive even integers, within the codec limit, and
their product must not exceed 16,777,216 pixels. VP9 high-bit-depth and 4:4:4 are not supported.

PTS values must be numeric, epoch zero, and strictly increasing after conversion
to a microsecond timebase. Numeric positive input durations are preserved to that
precision; otherwise the frame-rate hint provides a duration. The hint must be finite
and between 0.001 and 1,000,000 fps. Keyframe intervals are timestamp-based, between
one microsecond and one hour, so skipped inputs do not extend the keyframe interval.

Compression uses realtime, zero-lookahead operation with no intentional frame drops
or frame reordering. Average and constant bitrate modes are available. Call `update`
to change bitrate and frame-rate hints. Changing codec, dimensions,
bitrate mode, or keyframe interval requires a new encoder and is rejected by `update`.
`finish` drains the encoder and rejects further input; repeated calls return no
packets. `invalidate` releases resources and is safe to call repeatedly. Construct
new encoder/decoder instances to restart.

The decoder consumes raw compressed VP8/VP9 samples with a matching format description,
and returns NV12 frames with the packet PTS/duration and decoded full/video range.
The caller must demultiplex a container and supply packet timing; this module does not
read/write MP4, IVF, or WebM files, nor add RTP/Enhanced RTMP/TS framing.
Only decoded pixel range is signaled here; interpreting and attaching container colorimetry remains the caller’s responsibility.

Encoding and decoding follow the package's existing platform minimums; this module
does not depend on VideoToolbox pixel transfer. The libvpx 1.17.0 artifact supports arm64, including Apple silicon
simulators; it does not include Intel slices. Preserve the libvpx LICENSE and PATENTS
notices from libvpx-xcframework when distributing an app.

## Encoder statistics

Read ``VPXVideoEncoder/statistics`` on the encoder's actor or serial executor,
then send the value snapshot to VQMetrix's UI, history store, or report:

```swift
let snapshot = encoder.statistics
print(snapshot.submittedFrameCount, snapshot.outputPacketCount, snapshot.encodedByteCount)
print(snapshot.lastEncodingDuration, snapshot.averageEncodingDuration,
      snapshot.maximumEncodingDuration, snapshot.totalEncodingDuration)
```

Durations are monotonic wall-clock seconds inside successful native frame-encode calls,
including scheduling delays. They exclude caller conversion, input validation, output
copying, failed encode calls, and `finish()` flushing. They are not CPU utilization,
thermal state, energy use, or end-to-end latency. Packet/byte counters include drained
output. Counters live for the encoder's lifetime, survive invalidation, and are not
reset by settings updates. Snapshots are Codable and Sendable.

## Verification

Run `swift test --filter VPXVideoCodecTests` for both codec round trips, owned outputs,
keyframe timing, settings updates, unsupported input/dimension rejection, malformed packets, and lifecycle checks.
`swift run --package-path VPXHaishinKit/Tests/Consumer Consumer` exercises a separate
SwiftPM consumer importing only the public VPX API, without linking the HaishinKit core.

The published libvpx 1.17.0 artifact includes embedded DWARF debug information in its static libraries. Retain the final app archive and matching app dSYM for symbolication.

## Topics

### Encoding and decoding

- ``VPXVideoEncoder``
- ``VPXVideoDecoder``

### Configuration and failures

- ``VPXVideoCodecSettings``
- ``VPXVideoCodecSettings/Format``
- ``VPXVideoCodecSettings/BitRateMode``
- ``VPXVideoCodecError``

### Measurement

- ``VPXVideoEncoderStatistics``
