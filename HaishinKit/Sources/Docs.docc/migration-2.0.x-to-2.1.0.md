# Moving from 2.0.x APIs to 2.1.0

Update code written for HaishinKit 2.0.x to use the 2.1.0 APIs.

## Overview

This is a historical migration guide. Code examples refer to the versions shown in each section and may not match the current release.

### Package
In this version, we have restructured the module configuration. The RTMP-related features that were previously in HaishinKit have been moved to RTMPHaishinKit.

Several classes that were previously at the public level have been changed to package-level and are no longer exposed.

#### Import

##### 2.0.x
```swift
import HaishinKit

let connection = RTMPConnection()
```

##### 2.1.x
```swift
import HaishinKit
import RTMPHaishinKit

let connection = RTMPConnection()
```

#### Package Manager
[As previously announced](https://github.com/HaishinKit/HaishinKit.swift/discussions/1672), support for CocoaPods has been discontinued.

##### 2.0.x
- [x] CocoaPods
- [x] SwiftPM

##### 2.1.0
- [x] SwiftPM

### MediaMixer

#### Change in behavior
Since around iOS 18, when attaching a device during capture with AVCaptureMultiCamSession, the application’s UI becomes locked for several seconds. To address this, we have changed the behavior to start capture manually.

##### 2.0.x
```swift
import HaishinKit

let mixer = MediaMixer()
// Capture was automatically started under certain conditions.
await mixer.attachVideo(AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back))
await mixer.addOutput(view)
```

##### 2.1.0
```swift
import HaishinKit

let mixer = MediaMixer()
await mixer.attachVideo(AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back))
await mixer.addOutput(view)

// Calling startRunning() is now required.
await mixer.startRunning()
```

#### frameRate
Frame rate specification has been changed to allow separate settings for output configuration and camera input.

##### 2.0.x
```swift
await mixer.setFrameRate(fps)
```

##### 2.1.0
```swift
// Sets to video camera capture frameRate.
try? await mixer.configuration(video: 0) { video in
  do {
    try video.setFrameRate(fps)
  } catch {
    logger.error(error)
  }
}

// Sets to output frameRate.
try await mixer.setFrameRate(fps)
```
