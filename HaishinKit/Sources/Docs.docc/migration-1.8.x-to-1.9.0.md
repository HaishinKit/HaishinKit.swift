# Moving from 1.8.x APIs to 1.9.0

Update code written for HaishinKit 1.8.x to use the 1.9.0 APIs.

## Overview

This is a historical migration guide. Code examples refer to the versions shown in each section and may not match the current release.

### FeatureUtil.setEnabled(for: .multiTrackAudioMixing, isEnabled: true)
#### 1.8.0
```swift
FeatureUtil.setEnabled(for: .multiTrackAudioMixing, isEnabled: true)
let stream = RTMPStream(connection: rtmpConnection)
```

#### 1.9.0
```swift
let stream = RTMPStream(connection: rtmpConnection)
stream.isMultiTrackAudioMixingEnabled = true
```

### Multi Camera

#### 1.8.0
```swift
stream.videoMixerSettings = IOVideoMixerSettings(
  mode: .pip,
  cornerRadius: 16.0,
  regionOfInterest: .init(
    origin: CGPoint(x: 16, y: 16),
    size: .init(width: 160, height: 160)
  ),
  direction: .east
)
```

#### 1.9.0
I have revised the API to allow for flexible layout configurations.[Advanced Video Editing feature.](https://github.com/shogo4405/HaishinKit.swift/pull/1449)
There may be times when you want to use CMSampleBuffer directly for custom video editing or ReplayKit data. In such cases, please use `stream.videoMixerSettings.mode = .passthrough`.

```swift
stream.videoMixerSettings.mode = .offscreen
stream.screen.size = .init(width: 720, height: 1280)
stream.screen.backgroundColor = UIColor.white.cgColor

videoScreenObject.cornerRadius = 16.0
videoScreenObject.track = 1
videoScreenObject.horizontalAlignment = .left
videoScreenObject.layoutMargin = .init(top: 16, left: 16, bottom: 0, right: 0)
videoScreenObject.size = .init(width: 160 * 2, height: 90 * 2)
try? stream.screen.addChild(videoScreenObject)

stream.screen.startRunning()
```

### Apply VideoEffect
Up until version 1.8.x, VisualEffect was applied by default. Starting from version 1.9.0, it has been integrated as part of the Offscreen rendering API, so the following settings will be required.

#### 1.8.0
```swift
// no op
```

#### 1.9.0
```swift
stream.videoMixerSettings.mode = .offscreen
stream.screen.startRunning()
```
