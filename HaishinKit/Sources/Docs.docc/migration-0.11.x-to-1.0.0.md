# Moving from 0.11.x APIs to 1.0.0

Update code written for HaishinKit 0.11.x to use the 1.0.0 APIs.

## Overview

This is a historical migration guide. Code examples refer to the versions shown in each section and may not match the current release.

### Type-safed settings
#### 0.11.x
```swift
var rtmpStream = RTMPStream(connection: rtmpConnection)

rtmpStream.captureSettings = [
    "fps": 30, // FPS
    "sessionPreset": AVCaptureSession.Preset.medium.rawValue, // input video width/height
    "continuousAutofocus": false, // use camera autofocus mode
    "continuousExposure": false, //  use camera exposure mode
    // .preferredVideoStabilizationMode: AVCaptureVideoStabilizationMode.auto
]
rtmpStream.audioSettings = [
    "muted": false, // mute audio
    "bitrate": 32 * 1000,
    "sampleRate": sampleRate,
]
rtmpStream.videoSettings = [
    "width": 640, // video output width
    "height": 360, // video output height
    "bitrate": 160 * 1000, // video output bitrate
    "profileLevel": kVTProfileLevel_H264_Baseline_3_1, // H264 Profile require "import VideoToolbox"
    "maxKeyFrameIntervalDuration": 2, // key frame / sec
]
```
#### 1.0.0
```swift
var rtmpStream = RTMPStream(connection: rtmpConnection)

rtmpStream.captureSettings = [
    .fps: 30, // FPS
    .sessionPreset: AVCaptureSession.Preset.medium, // input video width/height
    .continuousAutofocus: false, // use camera autofocus mode
    .continuousExposure: false, //  use camera exposure mode
    // .preferredVideoStabilizationMode: AVCaptureVideoStabilizationMode.auto
]
rtmpStream.audioSettings = [
    .muted: false, // mute audio
    .bitrate: 32 * 1000,
    .sampleRate: sampleRate,
]
rtmpStream.videoSettings = [
    .width: 640, // video output width
    .height: 360, // video output height
    .bitrate: 160 * 1000, // video output bitrate
    .profileLevel: kVTProfileLevel_H264_Baseline_3_1, // H264 Profile require "import VideoToolbox"
    .maxKeyFrameIntervalDuration: 2, // key frame / sec
]
```
### Type-safed Event
#### 0.11.x
```swift
rtmpConnection.addEventListener(Event.RTMP_STATUS, selector: #selector(rtmpStatusHandler), observer: self)
```
#### 1.0.0
```swift
rtmpConnection.addEventListener(.rtmpStatus, selector: #selector(rtmpStatusHandler), observer: self)
```
### Remove asyncOrientation property.
#### 0.11.x
```swift
var rtmpStream = RTMPStream(connection: rtmpConnection)
rtmpStream.asyncOrientation = true
```
#### 1.0.0
```swift
var rtmpStream = RTMPStream(connection: rtmpConnection)
if let orientation = DeviceUtil.videoOrientation(by: UIApplication.shared.statusBarOrientation) {
    rtmpStream.orientation = orientation
}
NotificationCenter.default.addObserver(self, selector: #selector(on(_:)), name: UIDevice.orientationDidChangeNotification, object: nil)

@objc
private func on(_ notification: Notification) {
  guard let orientation = DeviceUtil.videoOrientation(by: UIApplication.shared.statusBarOrientation) else {
    return
  }
  rtmpStream.orientation = orientation
}
```
