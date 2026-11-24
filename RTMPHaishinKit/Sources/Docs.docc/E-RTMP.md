# Enhanced RTMP
The support status of Enhanced RTMP in RTMPHaishinKit.

## Overview
An extended RTMP standard called Enhanced RTMP is being developed by the Veovera Software Organization.
Please check [this repository](https://github.com/veovera/enhanced-rtmp/) for the specifications.

## Notice
Enhanced RTMP also requires support on the server side. Please check the support status of the server you are using.

## HDR with HEVC and HLG

To publish the mixer's 10-bit BT.2100 HLG output, configure both the mixer and the encoder before publishing:

```swift
import HaishinKit
import RTMPHaishinKit
import VideoToolbox

try await mixer.setDynamicRangeMode(.hdr)
var settings = await stream.videoSettings
settings.profileLevel = kVTProfileLevel_HEVC_Main10_AutoLevel as String
try await stream.setVideoSettings(settings)
```

The capture device must support the requested HDR format. The server must accept Enhanced RTMP HEVC and preserve the HEVC configuration and video data.

HLG color information is carried in the HEVC bitstream. Publishing preserves the source color primaries, transfer function, and YCbCr matrix. Playback reads this information from the HEVC sequence header and decodes HDR video to 10-bit pixel buffers; no receiver-side encoder settings are needed.

Use `PiPHKView` for system-managed video display. When using `MTHKView`, explicitly match its display mode to the mixer or expected incoming stream:

```swift
hkView.setDynamicRangeMode(.hdr)
```

Call `setDynamicRangeMode(.sdr)` when returning to SDR. Incoming frames do not change this selection. HDR mode converts HLG video to floating-point linear BT.2020 values for EDR display on iOS 16 or later and macOS; HDR brightness requires a compatible display. This preserves SDR video brightness when composing SDR assets into an HDR mixer. On tvOS, use `PiPHKView` for HDR display. Verify appearance on a physical HDR-capable device.

This supports HLG carried in HEVC. It does not implement `VideoPacketType.Metadata` (`colorInfo`), HDR10 mastering metadata, or Dolby Vision signaling.

## Supports Enhanced RTMP Status
### [v1](https://github.com/veovera/enhanced-rtmp/blob/main/docs/enhanced/enhanced-rtmp-v1.md)
AV1 playback uses the system VideoToolbox hardware decoder. The default connection advertises `av01` only when `VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1)` is true, and advertises decoding capability only. No software decoder or AV1 encoder is used by RTMPHaishinKit.

On a device without AV1 hardware decoding, incoming AV1 video is ignored while supported audio continues to play. The stream stays connected; an unsupported video codec does not stop audio playback.

Use the normal `RTMPStream.play` flow; no receiver-side encoder settings are needed. The server must support Enhanced RTMP AV1 and preserve its `av1C` sequence configuration and low-overhead OBU frame data. Configuration records without a Sequence Header OBU are completed from an in-band sequence header in the first sync sample. AV1 `CodedFrames` packets have no composition-time field; their RTMP timestamp is the presentation timestamp.

The receive tests include 8-bit and 10-bit Main-profile samples. Verify playback on a physical AV1-capable device; simulators and older hardware may not expose an AV1 hardware decoder. AV1 HDR metadata and display validation are outside this implementation.

See [AV1 playback and device support](https://docs.haishinkit.com/swift/latest/documentation/haishinkit/av1-playback) for model generations, official specifications, and the runtime capability check.

- [x] Enhancing onMetaData
- [ ] Defining Additional Video Codecs
  - [ ] Publish
    - [x] HEVC
    - [x] HEVC Main10 HDR (HLG)
    - [ ] VP9
    - [ ] AV1
  - [ ] Playback
    - [x] HEVC
    - [x] HEVC Main10 HDR (HLG)
    - [ ] VP9
    - [x] AV1 (VideoToolbox hardware decoding)
- [x] [Extending NetConnection connect Command](https://github.com/veovera/enhanced-rtmp/blob/main/docs/enhanced/enhanced-rtmp-v1.md#extending-netconnection-connect-command)
- [ ] Metadata Frame

### [v2](https://github.com/veovera/enhanced-rtmp/blob/main/docs/enhanced/enhanced-rtmp-v2.md)
- [ ] Enhancements to RTMP and FLV
- [ ] Enhancing onMetaData
- [ ] Reconnect Request
- [ ] Enhanced Video
  - [ ] Publish
    - [ ] VP8
    - [ ] AV1(HDR)
  - [ ] Playback
    - [ ] VP8
    - [ ] AV1(HDR)
- [ ] Enhanced Audio
  - [ ] Publish
    - [x] OPUS
  - [ ] Playback
    - [ ] OPUS
- [ ] Multitrack Streaming via Enhanced RTMP
- [x] [Enhancing NetConnection connect Command](https://github.com/veovera/enhanced-rtmp/blob/main/docs/enhanced/enhanced-rtmp-v2.md#enhancing-netconnection-connect-command)

