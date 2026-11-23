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

Call `setDynamicRangeMode(.sdr)` when returning to SDR. Incoming frames do not change this selection. HDR mode enables floating-point HLG output on iOS 16 or later and macOS; HDR brightness requires a compatible display. On tvOS, use `PiPHKView` for HDR display. Verify appearance on a physical HDR-capable device.

This supports HLG carried in HEVC. It does not implement `VideoPacketType.Metadata` (`colorInfo`), HDR10 mastering metadata, or Dolby Vision signaling.

## Supports Enhanced RTMP Status
### [v1](https://github.com/veovera/enhanced-rtmp/blob/main/docs/enhanced/enhanced-rtmp-v1.md)
Support for AV1 is planned to be implemented once the hardware becomes compatible.
- [x] Enhancing onMetaData
- [ ] Defining Additional Video Codecs
  - [ ] Publish
    - [x] HEVC
    - [ ] VP9
    - [ ] AV1
  - [ ] Playback
    - [x] HEVC
    - [ ] VP9
    - [ ] AV1
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

