# Moving from 0.3.x APIs to 0.4.x

Update code written for HaishinKit 0.3.x to use the 0.4.x APIs.

## Overview

This is a historical migration guide. Code examples refer to the versions shown in each section and may not match the current release.

### VideoIOView to LFView and GLLFView
* LFView supports preview for AVCaptureSession
* GLLFView supports RTMP playback and CIFilter image.

#### 0.3.x
```swift
var rtmpConnection:RTMPConnection = RTMPConnection()
var rtmpStream:RTMPStream = RTMPStream(rtmpConnection: rtmpConnection)

view.addSubview(rtmpStream.view)
```
#### 0.4.x
```swift
var lfView:LFView = LFView(frame: view.bounds)
// if you want to use VisualEffect plugin.
// var lfView:GLLFView = GLLFView(frame: view.bounds)
var rtmpConnection:RTMPConnection = RTMPConnection()
var rtmpStream:RTMPStream = RTMPStream(rtmpConnection: rtmpConnection)

lfView.attachStream(rtmpStream)
view.addSubview(lfView)
```

### AVMixer.class static methods are moved to DeviceUtil.class
#### 0.3.x
```swift
httpStream.attachCamera(AVMixer.deviceWithPosition(.Back))
```

#### 0.4.x
```swift
httpStream.attachCamera(DeviceUtil.deviceWithPosition(.Back))
```
