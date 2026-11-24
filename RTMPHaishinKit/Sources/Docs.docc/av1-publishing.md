# AV1 publishing with AOMHaishinKit

Publish externally encoded AV1 video through Enhanced RTMP.

Add both `AOMHaishinKit` and `RTMPHaishinKit` products to the application target.
RTMPHaishinKit has no dependency on libaom; the software encoder remains optional.
Encode caller-prepared video-range, 8-bit I420 frames with `AOMVideoEncoder`, then
pass its compressed samples to `RTMPStream.append`. The stream sends `av1C`
configuration followed by AV1 `CodedFrames`, preserving OBUs and keyframe flags.
AV1 timestamps use PTS and have no HEVC composition-time field. A zero-based input
timeline is supported. The server must support Enhanced RTMP AV1 ingestion.

## Publishing connection

Advertise encoding explicitly on this connection, including on hosts without AV1
hardware decoding. `0x02` is Enhanced RTMP's `canEncode` bit; retain the default
decode capability when available.

```swift
import AOMHaishinKit
import CoreMedia
import RTMPHaishinKit

// Run on a serial worker; software encoding is synchronous.
func publishPreparedAV1(_ frames: [CMSampleBuffer], settings: AOMVideoCodecSettings) async throws {
    var fourCCs = RTMPConnection.supportedFourCcList
    if !fourCCs.contains("av01") { fourCCs.append("av01") }
    var capabilities = RTMPConnection.supportedVideoFourCcInfoMap
    capabilities["av01"] = (capabilities["av01"] as? Int ?? 0) | 0x02
    let connection = RTMPConnection(fourCcList: fourCCs, videoFourCcInfoMap: capabilities)
    let stream = RTMPStream(connection: connection)
    let encoder = try AOMVideoEncoder(settings: settings)
    defer { encoder.invalidate() }
    try await connection.connect("rtmp://localhost/live")
    do {
        try await stream.publish("av1") { generated in
            var metadata = generated
            metadata["videocodecid"] = "av01"
            metadata["width"] = settings.videoSize.width
            metadata["height"] = settings.videoSize.height
            metadata["videodatarate"] = settings.bitRate / 1000
            metadata["framerate"] = settings.expectedFrameRate
            return metadata
        }
        for frame in frames {
            for packet in try encoder.encode(frame) { await stream.append(packet) }
        }
        for packet in try encoder.finish() { await stream.append(packet) }
        try await stream.close()
        try await connection.close()
    } catch {
        try? await connection.close()
        throw error
    }
}
```

Prepare frames at the configured size and pace input according to its timestamps
for live publishing. Pixel conversion, resizing, and capture remain the application's
responsibility. `VideoCodecSettings` configures the built-in VideoToolbox encoder;
the software AV1 encoder uses `AOMVideoCodecSettings` separately. This path supports
8-bit SDR publishing; AV1 HDR encoding is not included.

The normal audio path remains available for AAC or Opus. Applications feeding a
MediaMixer into their own video encoder should route only the resulting compressed
video samples to this stream, so the built-in encoder does not encode the same video.
