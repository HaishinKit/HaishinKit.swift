# Moving from 1.3.x APIs to 1.4.0

Update code written for HaishinKit 1.3.x to use the 1.4.0 APIs.

## Overview

This is a historical migration guide. Code examples refer to the versions shown in each section and may not match the current release.

### CaptureSettings
#### 1.3.0
```swift
stream.captureSettings = [
    .fps: 30, // FPS
    .sessionPreset: AVCaptureSession.Preset.medium, // input video width/height
    // .isVideoMirrored: false,
    // .continuousAutofocus: false, // use camera autofocus mode
    // .continuousExposure: false, //  use camera exposure mode
    // .preferredVideoStabilizationMode: AVCaptureVideoStabilizationMode.auto
]
```

#### 1.4.0
```swift
stream.frameRate = 30.0
stream.sessionPreset = .medium

stream.videoCapture(for: 0).isVideoMirrored = false
// stream.videoCapture(for: 0).preferredVideoStabilizationMode = AVCaptureVideoStabilizationMode.auto

let device = AVCaptureDevice.default(for: AVMediaType.video) // or stream.videoCapture(for: 0).device
do {
  try device.lockForConfiguration()
  device.exposurePointOfInterest = point
  device.exposureMode = continuousExposure ? .continuousAutoExposure : .autoExpose
  device.unlockForConfiguration()
} catch let error as NSError {
  logger.error("while locking device for exposurePointOfInterest: \(error)")
}
```

### muted
#### 1.3.0
```swift
stream.audioSettings[.muted] = true
stream.videoSettings[.muted] = true
```
#### 1.4.0
```swift
stream.hasAudio = false
stream.hasVideo = false
```
### Recording
#### 1.3.0
```swift
stream.recordSettings = [
  AVMediaType.audio: [
  ],
  AVMediaType.video: [
  ]
]
stream.startRecording()
```

#### 1.4.0
```swift
stream.startRecording([
  AVMediaType.audio: [
  ],
  AVMediaType.video: [
  ]
])
```

### ScreenCapture on iOS
#### 1.3.0
```swift
stream.attachScreen(ScreenCaptureSession(shared: UIApplication.shared))
```

#### 1.4.0
```swift
screen = IOUIScreenCaptureUnit(shared: UIApplication.shared)
screen.delegate = stream
screen.startRunning()

stream.publish("streamName")
```
