# Checking system codec support

Inspect OS-reported video and audio capabilities in the iOS, macOS, tvOS and
visionOS example applications. The inspector uses the system APIs; it does not
include bundled AOM/VPX implementations or establish support in a streaming protocol.

## Open the inspector

| Sample | Location |
| --- | --- |
| iOS | Preference → Device codecs |
| macOS | Settings → Device codecs |
| tvOS | Settings → Settings tab → Device codecs |
| visionOS | Device codecs above the playback view |

The screen has Video and Audio lists, separate encoding and decoding information,
and expandable format identifiers. Refresh reads the current process's reported
capabilities again while keeping the current list visible. The capability queries do not open a camera, microphone, audio session or network connection.

## Copy a report

On iOS, macOS and visionOS, **Copy** writes the complete Video and Audio report,
including encoder implementation details, query errors, OS/platform information and
interpretation limits, to the system clipboard. Both categories are copied even
when only one is visible. Field labels use English so reports can be compared
across app languages. Copying happens only when the button is pressed.

The tvOS SDK does not expose a public clipboard API. That sample shows an
explanation instead of a Copy action.

## VideoToolbox

[VTCopyVideoEncoderList](https://developer.apple.com/documentation/videotoolbox/vtcopyvideoencoderlist(_:_:))
returns registered encoder implementations. The inspector displays their names,
identifiers and reported hardware/software classification. It requests
`kVTVideoEncoderListOption_IncludeStandardDefinitionDVEncoders` so installed
standard-definition DV encoders are included. A missing acceleration
flag remains unspecified. Absence from a successful list is shown as **Not listed**;
a failed query is shown as **Unknown**, with its error status.

[VTIsHardwareDecodeSupported](https://developer.apple.com/documentation/videotoolbox/vtishardwaredecodesupported(_:))
only answers the hardware-decoding question. The inspector queries seven selected
common codec types (H.264, HEVC, AV1, VP9, ProRes 422, ProRes 4444 and JPEG), plus
any types returned by encoder enumeration. This is not a complete decoder inventory;
formats outside that set are not queried. A negative result does not rule out
software decoding. The **Hardware decode** column therefore uses **Not reported**,
not a general “codec unsupported” result. The inspector does not create decoding
sessions with incomplete format descriptions, which could otherwise give false
negative results for formats requiring parameter sets or other initialization data.

Encoder enumeration does not guarantee that a compression session can be created
with every profile, resolution, frame rate, latency setting or concurrent workload.
Session creation and actual frame processing are separate checks. Simulator results
can reflect host/simulator facilities and must not be treated as physical-device results.

## AudioConverter and AVAudioConverter

The audio list reads `kAudioFormatProperty_EncodeFormatIDs` and
`kAudioFormatProperty_DecodeFormatIDs` through `AudioFormatGetPropertyInfo` and
`AudioFormatGetProperty`. These are the system-reported valid output/input format
IDs for AudioConverter. See Apple's
[audio format property reference](https://developer.apple.com/documentation/audiotoolbox/1577853-audio-format-property-identifier).

**Listed** is a format-level report. It does not promise every conversion between
listed formats. An [AVAudioConverter](https://developer.apple.com/documentation/avfaudio/avaudioconverter)
still needs concrete input and output formats, sample rates, channel layouts and
codec settings. Some compressed inputs also need a magic cookie. Creating a
converter is itself only a construction check; successful conversion requires
supplying valid data and checking conversion status and errors.

For example, a PCM-to-AAC construction check can use:

```swift
import AVFAudio
import AudioToolbox

let pcm = AVAudioFormat(
    commonFormat: .pcmFormatFloat32,
    sampleRate: 48_000,
    channels: 2,
    interleaved: false
)
let aac = AVAudioFormat(settings: [
    AVFormatIDKey: kAudioFormatMPEG4AAC,
    AVSampleRateKey: 48_000,
    AVNumberOfChannelsKey: 2
])
if let pcm, let aac, let converter = AVAudioConverter(from: pcm, to: aac) {
    // Construction succeeded for this format pair on this OS/device.
    // Next, supply valid PCM buffers to convert(to:error:withInputFrom:)
    // and check its returned status and error. No conversion has happened yet.
    print(converter.outputFormat)
}
```

The sample inspector deliberately does not allocate converters or encode/decode
probe frames for every entry. It keeps the list distinct from a conversion test
and avoids reserving scarce codec instances while a stream may already be running.
Use an actual converter/session and representative data to validate the particular
settings and container or streaming protocol used by an application.
