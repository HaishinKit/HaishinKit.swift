# HaishinKit for iOS, macOS, tvOS, visionOS and [Android](https://github.com/shogo4405/HaishinKit.kt).
[![GitHub Stars](https://img.shields.io/github/stars/shogo4405/HaishinKit.swift?style=social)](https://github.com/shogo4405/HaishinKit.swift/stargazers)
[![Release](https://img.shields.io/github/v/release/shogo4405/HaishinKit.swift)](https://github.com/shogo4405/HaishinKit.swift/releases/latest)
[![Platform Compatibility](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fshogo4405%2FHaishinKit.swift%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/shogo4405/HaishinKit.swift)
[![Swift Compatibility](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fshogo4405%2FHaishinKit.swift%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/shogo4405/HaishinKit.swift)
[![GitHub license](https://img.shields.io/badge/License-BSD%203--Clause-blue.svg)](https://raw.githubusercontent.com/shogo4405/HaishinKit.swift/master/LICENSE.md)
[![GitHub Sponsor](https://img.shields.io/static/v1?label=Sponsor&message=%E2%9D%A4&logo=GitHub&color=ff69b4)](https://github.com/sponsors/shogo4405)

* Camera and Microphone streaming library via RTMP and SRT for iOS, macOS, tvOS and visionOS.
* README.md contains unreleased content, which can be tested on the main branch.
* [API Documentation](https://docs.haishinkit.com/swift/latest/)

## 💖 Sponsors
<p align="center">
  <br />
  <br />
  <a href="https://github.com/sponsors/shogo4405">Sponsorship</a>
  <br />
  <br />
  <br />
</p>

## 💬 Communication
* If you need help with making LiveStreaming requests using HaishinKit, use a [GitHub Discussions](https://github.com/shogo4405/HaishinKit.swift/discussions) with **Q&A**.
* If you'd like to discuss a feature request, use a [GitHub Discussions](https://github.com/shogo4405/HaishinKit.swift/discussions) with **Idea**
* If you met a HaishinKit's bug🐛, use a [GitHub Issue](https://github.com/shogo4405/HaishinKit.swift/issues) with **Bug report template**
  - The trace level log is very useful. Please set `LBLogger.with(HaishinKitIdentifier).level = .trace`. 
  - If you don't use an issue template. I will immediately close the your issue without a comment.
* If you **want to contribute**, submit a pull request with a pr template.
* If you want to support e-mail based communication without GitHub.
  - Consulting fee is [$50](https://www.paypal.me/shogo4405/50USD)/1 incident. I'm able to response a few days.
* [Discord chatroom](https://discord.com/invite/8nkshPnanr).
* 日本語が分かる方は、日本語でのコミニケーションをお願いします！

## 🌏 Related projects
Project name    |Notes       |License
----------------|------------|--------------
[HaishinKit for Android.](https://github.com/shogo4405/HaishinKit.kt)|Camera and Microphone streaming library via RTMP for Android.|[BSD 3-Clause "New" or "Revised" License](https://github.com/shogo4405/HaishinKit.kt/blob/master/LICENSE.md)
[HaishinKit for Flutter.](https://github.com/shogo4405/HaishinKit.dart)|Camera and Microphone streaming library via RTMP for Flutter.|[BSD 3-Clause "New" or "Revised" License](https://github.com/shogo4405/HaishinKit.dart/blob/master/LICENSE.md)

## 🎨 Features
### RTMP
- [x] Authentication
- [x] Publish and Recording
- [x] _Playback (Beta)_
- [x] [Adaptive bitrate streaming](../../issues/1308)
- [ ] Action Message Format
  - [x] AMF0
  - [ ] AMF3
- [x] SharedObject
- [x] RTMPS
  - [x] Native (RTMP over SSL/TLS)
  - [x] _Tunneled (RTMPT over SSL/TLS) (Technical Preview)_
- [x] _RTMPT (Technical Preview)_
- [x] ReplayKit Live as a Broadcast Upload Extension
- [x] [Enhanced RTMP](https://github.com/veovera/enhanced-rtmp)

### SRT(beta)
- [x] Publish and Recording (H264/HEVC/AAC)
- [x] Playback(beta)
- [ ] mode
  - [x] caller
  - [x] listener
  - [ ] rendezvous

### Offscreen Rendering.
Through off-screen rendering capabilities, it is possible to display any text or bitmap on a video during broadcasting or viewing. This allows for various applications such as watermarking and time display.
|Ingest|Playback|
|:---:|:---:|
|<img width="961" alt="" src="https://github.com/user-attachments/assets/aaf6c06f-d2de-43c1-a435-90907f370977">|<img width="849" alt="" src="https://github.com/user-attachments/assets/0a07b418-aa56-41cb-8e6d-e12596b25ae8">|

<details>
<summary>Example</summary>
  
```swift
stream.videoMixerSettings.mode = .offscreen
stream.screen.startRunning()
textScreenObject.horizontalAlignment = .right
textScreenObject.verticalAlignment = .bottom
textScreenObject.layoutMargin = .init(top: 0, left: 0, bottom: 16, right: 16)

stream.screen.backgroundColor = UIColor.black.cgColor

let videoScreenObject = VideoTrackScreenObject()
videoScreenObject.cornerRadius = 32.0
videoScreenObject.track = 1
videoScreenObject.horizontalAlignment = .right
videoScreenObject.layoutMargin = .init(top: 16, left: 0, bottom: 0, right: 16)
videoScreenObject.size = .init(width: 160 * 2, height: 90 * 2)
_ = videoScreenObject.registerVideoEffect(MonochromeEffect())

let imageScreenObject = ImageScreenObject()
let imageURL = URL(fileURLWithPath: Bundle.main.path(forResource: "game_jikkyou", ofType: "png") ?? "")
if let provider = CGDataProvider(url: imageURL as CFURL) {
    imageScreenObject.verticalAlignment = .bottom
    imageScreenObject.layoutMargin = .init(top: 0, left: 0, bottom: 16, right: 0)
    imageScreenObject.cgImage = CGImage(
        pngDataProviderSource: provider,
        decode: nil,
        shouldInterpolate: false,
    intent: .defaultIntent
    )
} else {
    logger.info("no image")
}

let assetScreenObject = AssetScreenObject()
assetScreenObject.size = .init(width: 180, height: 180)
assetScreenObject.layoutMargin = .init(top: 16, left: 16, bottom: 0, right: 0)
try? assetScreenObject.startReading(AVAsset(url: URL(fileURLWithPath: Bundle.main.path(forResource: "SampleVideo_360x240_5mb", ofType: "mp4") ?? "")))
try? stream.screen.addChild(assetScreenObject)
try? stream.screen.addChild(videoScreenObject)
try? stream.screen.addChild(imageScreenObject)
try? stream.screen.addChild(textScreenObject)
stream.screen.delegate = self
```

</details>

### Rendering
|Features|[PiPHKView](https://shogo4405.github.io/HaishinKit.swift/Classes/PiPHKView.html)|[MTHKView](https://shogo4405.github.io/HaishinKit.swift/Classes/MTHKView.html)|
|-|:---:|:---:|
|Engine|AVSampleBufferDisplayLayer|Metal|
|Publish|✔|✔|
|Playback|✔|✔|
|VisualEffect|✔|✔|
|MultiCamera|✔|✔|
|PictureInPicture|✔|<br />|

### Others
- [x] tvOS 17.0 for AVCaptureSession.
- [x] [Support multitasking camera access.](https://developer.apple.com/documentation/avfoundation/capture_setup/accessing_the_camera_while_multitasking)
- [x] Support "Allow app extension API only" option

## 🐾 Examples
Examples project are available for iOS with UIKit, iOS with SwiftUI, macOS and tvOS. Example macOS requires Apple Silicon mac.
- [x] Camera and microphone publish.
- [x] Playback
```sh
git clone https://github.com/shogo4405/HaishinKit.swift.git
cd HaishinKit.swift
carthage bootstrap --platform iOS,macOS,tvOS --use-xcframeworks
open HaishinKit.xcodeproj
```

## 🌏 Requirements

### Development
|Version|Xcode|Swift|
|:----:|:----:|:----:|
|1.9.0+|15.4+|5.10+|
|1.8.0+|15.3+|5.9+|
|1.7.0+|15.0+|5.9+|
|1.6.0+|15.0+|5.8+|

### OS
|-|iOS|tvOS|macOS|visionOS|watchOS|
|:----|:----:|:----:|:----:|:----:|:----:|
|HaishinKit|13.0+|13.0+|10.15+|1.0+|-|
|SRTHaishinKit|13.0+|13.0+|13.0+|1.0+|-|

### Cocoa Keys
Please contains Info.plist.

**iOS 10.0+**
* NSMicrophoneUsageDescription
* NSCameraUsageDescription

**macOS 10.14+**
* NSMicrophoneUsageDescription
* NSCameraUsageDescription

**tvOS 17.0+**
* NSMicrophoneUsageDescription
* NSCameraUsageDescription

## 🔧 Installation
HaishinKit has a multi-module configuration. If you want to use the SRT protocol, please use SRTHaishinKit.
|  | HaishinKit | SRTHaishinKit |
| - | :- | :- |
| SPM | https://github.com/shogo4405/HaishinKit.swift | https://github.com/shogo4405/HaishinKit.swift |
| CocoaPods |<pre>def import_pods<br>  pod 'HaishinKit', '~> 1.9.6<br>end</pre>|<pre>def import_pods<br>  pod 'SRTHaishinKit', '~> 1.9.6<br>end</pre>|
| Carthage | github "shogo4405/HaishinKit.swift" ~> 1.9.6 | Not available. |
* SRTHaishinKit via CocoaPods supports only iOS and tvOS.

## 🔧 Prerequisites
Make sure you setup and activate your AVAudioSession iOS.
```swift
import AVFoundation
let session = AVAudioSession.sharedInstance()
do {
    try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
    try session.setActive(true)
} catch {
    print(error)
}
```

## 📓 RTMP Usage
### Ingest
```swift
let connection = RTMPConnection()
let stream = RTMPStream(connection: connection)

stream.attachAudio(AVCaptureDevice.default(for: .audio)) { _, error in
  if let error {
    logger.warn(error)
  }
}

stream.attachCamera(AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back), track: 0) { _, error in
  if let error {
    logger.warn(error)
  }
}

let hkView = MTHKView(frame: view.bounds)
hkView.videoGravity = AVLayerVideoGravity.resizeAspectFill
hkView.attachStream(stream)

// add ViewController#view
view.addSubview(hkView)

connection.connect("rtmp://localhost/appName/instanceName")
stream.publish("streamName")
```

### Playback
```swift
let connection = RTMPConnection()
let stream = RTMPStream(connection: connection)

let hkView = MTHKView(frame: view.bounds)
hkView.videoGravity = AVLayerVideoGravity.resizeAspectFill
hkView.attachStream(stream)

// add ViewController#view
view.addSubview(hkView)

connection.connect("rtmp://localhost/appName/instanceName")
stream.play("streamName")
```

### Authentication
```swift
var connection = RTMPConnection()
connection.connect("rtmp://username:password@localhost/appName/instanceName")
```

## 📓 SRT Usage
### Ingest
```swift
let connection = SRTConnection()
let stream = SRTStream(connection: connection)
stream.attachAudio(AVCaptureDevice.default(for: .audio)) { error in
    // print(error)
}
stream.attachCamera(AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back), track: 0) { _, error in
  if let error {
    logger.warn(error)
  }
}

let hkView = HKView(frame: view.bounds)
hkView.videoGravity = AVLayerVideoGravity.resizeAspectFill
hkView.attachStream(rtmpStream)

// add ViewController#view
view.addSubview(hkView)

connection.connect("srt://host:port?option=foo")
stream.publish()
```

### Playback
```swift
let connection = SRTConnection()
let stream = SRTStream(connection: connection)

let hkView = MTHKView(frame: view.bounds)
hkView.videoGravity = AVLayerVideoGravity.resizeAspectFill
hkView.attachStream(rtmpStream)

// add ViewController#view
view.addSubview(hkView)

connection.connect("srt://host:port?option=foo")
stream.play()
```

## 📓 Settings
### 📹 AVCaptureSession
```swift
stream.frameRate = 30
stream.sessionPreset = AVCaptureSession.Preset.medium

// Do not call beginConfiguration() and commitConfiguration() internally within the scope of the method, as they are called internally.
stream.configuration { session in
  session.automaticallyConfiguresApplicationAudioSession = true
}
```

### 🔊 Audio
#### [Capture](https://docs.haishinkit.com/swift/latest/Classes/IOAudioCaptureUnit.html)
Specifies the capture capture settings.
```swift
let front = AVCaptureDevice.default(for: .audio)
stream.attachAudio(front, track: 0) { audioUnit, error in
}
```

#### [AudioMixerSettings](https://docs.haishinkit.com/swift/latest/Structs/IOAudioMixerSettings.html)
If you want to mix multiple audio tracks, please enable the feature flag.
```swift
stream.isMultiTrackAudioMixingEnabled = true
```

When you specify the sampling rate, it will perform resampling. Additionally, in the case of multiple channels, downsampling can be applied.
```swift
// Setting the value to 0 will be the same as the value specified in mainTrack.
stream.audioMixerSettings = IOAudioMixerSettings(
  sampleRate: Float64 = 44100,
  channels: UInt32 = 0,
)

stream.audioMixerSettings.isMuted = false
stream.audioMixerSettings.mainTrack = 0
stream.audioMixerSettings.tracks = [
  0: .init(
    isMuted: Bool = false,
    downmix: Bool = true,
    channelMap: [Int]? = nil
  )
]
```

#### [AudioCodecSettings](https://docs.haishinkit.com/swift/latest/Structs/AudioCodecSettings.html)
```swift
/// Specifies the bitRate of audio output.
stream.audioSettings.bitrate = 64 * 1000
/// Specifies the mixes the channels or not. Currently, it supports input sources with 4, 5, 6, and 8 channels.
stream.audioSettings.downmix = true
/// Specifies the map of the output to input channels.
 stream.audioSettings.channelMap: [Int]? = nil
```

### 🎥 Video
#### [Capture](https://docs.haishinkit.com/swift/latest/Classes/IOVideoCaptureUnit.html)
Specifies the video capture settings.
```swift
let front = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
stream.attachCamera(front, track: 0) { videoUnit, error in
  videoUnit?.isVideoMirrored = true
  videoUnit?.preferredVideoStabilizationMode = .standard
  videoUnit?.colorFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
}
```

#### [VideoMixerSettings](https://docs.haishinkit.com/swift/latest/Structs/IOVideoMixerSettings.html)
```swift
/// Specifies the image rendering mode.
stream.videoMixerSettings.mode = .passthrough or .offscreen
/// Specifies the muted indicies whether freeze video signal or not.
stream.videoMixerSettings.isMuted = false
/// Specifies the main track number.
stream.videoMixerSettings.mainTrack = 0
```

#### [VideoCodecSettings](https://docs.haishinkit.com/swift/latest/Structs/VideoCodecSettings.html)
```swift
stream.videoSettings = .init(
  videoSize: .init(width: 854, height: 480),
  profileLevel: kVTProfileLevel_H264_Baseline_3_1 as String,
  bitRate: 640 * 1000,
  maxKeyFrameIntervalDuration: 2,
  scalingMode: .trim,
  bitRateMode: .average,
  allowFrameReordering: nil,
  isHardwareEncoderEnabled: true
)
```

### ⏺️ Recording
Internally, I am now handling data with more than 3 channels. If you encounter audio issues with IOStreamRecorder, it is recommended to set it back to a maximum of 2 channels when saving locally.
```swift
let channels = max(stream.audioInputFormats[0].channels ?? 1, 2)
stream.audioMixerSettings = .init(sampleRate: 0, channels: channels)
```

```swift
// Specifies the recording settings. 0" means the same of input.
var recorder = IOStreamRecorder()
stream.addObserver(recorder)

recorder.settings = [
  AVMediaType.audio: [
    AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
    AVSampleRateKey: 0,
    AVNumberOfChannelsKey: 0,
    // AVEncoderBitRateKey: 128000,
  ],
  AVMediaType.video: [
    AVVideoCodecKey: AVVideoCodecH264,
    AVVideoHeightKey: 0,
    AVVideoWidthKey: 0,
    /*
    AVVideoCompressionPropertiesKey: [
      AVVideoMaxKeyFrameIntervalDurationKey: 2,
      AVVideoProfileLevelKey: AVVideoProfileLevelH264Baseline30,
      AVVideoAverageBitRateKey: 512000
    ]
    */
  ]
]

recorder.startRunning()
// recorder.stopRunning()
```

## 📜 Known Issues
- [Xcode15.4+, High CPU Usage and Increse Memory with SPM](https://github.com/shogo4405/HaishinKit.swift/issues/1512)

## 📜 License
BSD-3-Clause
