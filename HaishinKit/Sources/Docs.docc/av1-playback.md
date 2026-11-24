# AV1 playback and device support

Check device capabilities before receiving AV1 video through VideoToolbox.

## Overview

RTMPHaishinKit receives AV1 through Enhanced RTMP and decodes it with the system VideoToolbox hardware decoder. AV1 publishing, software-decoder fallback, and AV1 transport through SRT or WebRTC are not part of this implementation.

On devices without an AV1 hardware decoder, AV1 video packets are ignored while supported audio, such as AAC, continues to play. The connection remains open. Applications should show an audio-only state rather than assume that every incoming stream can display video.

## Device reference

The table identifies generations whose official specifications list AV1 playback or an AV1 decode engine. It is a hardware reference, not a list of devices individually tested with HaishinKit. Checked on November 24, 2026.

| Family | AV1-capable model or generation | Chip | Official reference |
|:--|:--|:--|:--|
| iPhone | iPhone 15 Pro / Pro Max (2023): the first iPhone generation with a dedicated AV1 decoder | A17 Pro | [Introduction and decoder details](https://www.apple.com/newsroom/2023/09/apple-unveils-iphone-15-pro-and-iphone-15-pro-max/) |
| iPhone | iPhone 16 / 16 Plus (2024); AV1 is not limited to Pro models in this generation | A18 | [iPhone 16 specifications](https://support.apple.com/en-us/121029) |
| iPhone | iPhone 18 Pro / Pro Max (2026) | See model specifications | [iPhone 18 Pro specifications](https://www.apple.com/iphone-18-pro/specs/) |
| iPad mini | iPad mini (A17 Pro, 2024; commonly called the 7th generation) | A17 Pro | [Specifications](https://support.apple.com/en-mide/121456) |
| iPad mini | iPad mini (A20 Pro, 2026) | A20 Pro | [Specifications](https://support.apple.com/en-us/149482) |
| iPad Air | 11-inch / 13-inch iPad Air, M3 generation (2025) | M3 | [11-inch specifications](https://support.apple.com/en-us/122241), [13-inch specifications](https://support.apple.com/en-us/122242) |
| iPad Air | 11-inch / 13-inch iPad Air, M4 generation (2026) | M4 | [Specifications](https://support.apple.com/en-us/126471) |
| iPad Pro | 11-inch / 13-inch iPad Pro, M4 generation (2024) | M4 | [11-inch specifications](https://support.apple.com/en-gb/119892), [13-inch specifications](https://support.apple.com/en-us/119891) |
| iPad Pro | 11-inch / 13-inch iPad Pro, M5 generation (2025) | M5 | [11-inch specifications](https://support.apple.com/en-euro/125406), [13-inch specifications](https://support.apple.com/en-ie/125407) |
| Mac | M3-generation Macs, beginning with MacBook Pro in late 2023 | M3 family | [MacBook Pro with M3](https://support.apple.com/en-gb/117735), [M3-family decoder details](https://www.apple.com/newsroom/2023/10/apple-unveils-m3-m3-pro-and-m3-max-the-most-advanced-chips-for-a-personal-computer/) |
| Mac | MacBook Pro, M4 generation (2024) | M4 | [Specifications](https://support.apple.com/en-gb/121552) |
| Mac | MacBook Pro, M5 generation (2025), and M5 Pro / Max generation (2026) | M5 / M5 Pro / M5 Max | [M5 specifications](https://support.apple.com/en-ie/125405), [M5 Pro / Max specifications](https://support.apple.com/en-gb/126318) |
| Mac | MacBook Neo | A18 Pro | [Specifications](https://www.apple.com/macbook-neo/specs/) |
| Apple TV | Apple TV 4K (4th generation, 2026) | A19 | [Specifications](https://support.apple.com/en-us/149359) |

This is not an exhaustive catalog of newer models. For newer M-series Macs and iPads, check the exact model's Media Engine specifications for AV1 decode. iPad generation numbering differs between screen sizes, so chip and model names are more precise than a single generation number for the entire iPad range.

Do not infer support from a recent purchase date, a Pro name, or an M-series chip alone. For example, [iPad (A16)](https://www.apple.com/ipad-11/specs/) and [Apple TV 4K (3rd generation, A15 Bionic)](https://support.apple.com/en-ie/111839) do not list AV1 in their video playback specifications. M1- and M2-generation hardware predates the M3 AV1 decode engine. Always use the runtime check below for the current device.

## Runtime check

Use [VTIsHardwareDecodeSupported](https://developer.apple.com/documentation/videotoolbox/vtishardwaredecodesupported(_:)) instead of a hard-coded device list:

```swift
import VideoToolbox

func canReceiveAV1Video() -> Bool {
    guard #available(iOS 17.0, tvOS 17.0, *) else {
        return false
    }
    return VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1)
}
```

The connection's default Enhanced RTMP capabilities include `av01` only when hardware decoding is available, and advertise decode capability only. Decoder creation also requires hardware acceleration. An installed software decoder does not enable this receive path.

Hardware availability does not guarantee that every AV1 profile, bit depth, resolution, or frame rate can be decoded. The actual format must also be accepted by `VTDecompressionSessionCreate`. Simulators may not expose the same decoder as the physical device.

## Playback and validation

Use the normal RTMP playback flow, including attaching an `AudioPlayer` for sound. No receiver-side video encoder settings are needed. See [Enhanced RTMP](https://docs.haishinkit.com/swift/latest/documentation/rtmphaishinkit/e-rtmp) for packet and server requirements.

Tests include real 8-bit and 10-bit Main-profile samples, configuration recovery from an in-band sequence header, and AAC decoding while unsupported AV1 video is ignored. Hardware decode tests run only on AV1-capable systems. Verify decoding and display with the intended stream on a physical device; the hardware reference above does not imply that every model has completed that validation. AV1 HDR metadata and display validation are outside the current implementation.

Physical playback has been verified on iPad mini (A17 Pro), running iPadOS 27.2, with 320 × 180 AV1 video at 15 fps encoded by a Pixel 8 hardware encoder. The stream was relayed through MediaMTX without re-encoding the video, with an AAC test tone generated by the relay host. Both video display and audible playback were confirmed. This does not establish support for every AV1 profile or higher resolution.
