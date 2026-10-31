# Moving from 1.7.x APIs to 1.8.0

Update code written for HaishinKit 1.7.x to use the 1.8.0 APIs.

## Overview

This is a historical migration guide. Code examples refer to the versions shown in each section and may not match the current release.

### IOStream#attachAudio

#### 1.7.0
```swift
stream.attachAudio(AVCaptureDevice.default(for: .audio), automaticallyConfiguresApplicationAudioSession: true) { error in
    // print(error)
}
```

#### 1.8.0
```swift
stream.configuration { session in
    session.automaticallyConfiguresApplicationAudioSession = true
}

stream.attachAudio(AVCaptureDevice.default(for: .audio), track: 0) { unit, error in
}
```

### IOStream#attachVideo

#### 1.7.0
```swift
stream.attachCamera(AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back), channel: 0) { _, error in
  if let error {
    logger.warn(error)
  }
}
```

#### 1.8.0
```swift
stream.attachCamera(AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back), track: 0) { _, error in
  if let error {
    logger.warn(error)
  }
}
```


### IOStreamDelegate
#### 1.7.0
Removed.
```swift
/// The interface an IOStream uses to inform its delegate.
public protocol IOStreamDelegate: AnyObject {
    /// Tells the receiver to an audio packet incoming.
    func stream(_ stream: IOStream, didOutput audio: AVAudioBuffer, when: AVAudioTime)
    /// Tells the receiver to a video incoming.
    func stream(_ stream: IOStream, didOutput video: CMSampleBuffer)
}

setream.delegate = delegate.
```

#### 1.8.0
```swift
/// A delegate protocol your app implements to receive capture stream output events.
public protocol IOStreamObserver: AnyObject {
    /// Tells the receiver to an audio packet incoming.
    func stream(_ stream: IOStream, didOutput audio: AVAudioBuffer, when: AVAudioTime)
    /// Tells the receiver to a video incoming.
    func stream(_ stream: IOStream, didOutput video: CMSampleBuffer)
}

class MyStreamObserver: IOStreamObserver {
}

val observer = MyStreamObserver()
stream.addObserver(observer)
```

### IOStream.audioSettings
#### 1.7.x
```swift
stream.audioSettings = AudioCodecSettings(
  bitRate: Int = 64 * 1000,
  sampleRate: Float64 = 0,
  channels: UInt32 = 0,
  downmix: Bool = false,
  channelMap: [Int]? = nil
)
```

#### 1.8.0
Settings for audio mixing processes such as sample rate conversion have been transferred to audioMixerSettings.
```swift
stream.audioMixerSettings = .init(sampleRate: 0, channels: 0)
stream.audioMixerSettings.tracks[0] = [
  0: .init(
    isMuted: Bool = false,
    downmix: Bool = true,
    channelMap: [Int]? = nil
  )
]

stream.audioSettings.bitRate = 64 * 1000
```

### Recording
#### 1.7.1
```swift
// Start recording.
stream.isRecording
stream.startRecording(self, settings: settings)

// Stop recording.
stream.stopRecording()
```

#### 1.8.0
Internally, I am now handling data with more than 3 channels. If you encounter audio issues with IOStreamRecorder, it is recommended to set it back to a maximum of 2 channels when saving locally.
```swift
let channels = max(stream.audioInputFormats[0]?.channels ?? 1, 2)
stream.audioMixerSettings = .init(sampleRate: 0, channels: channels)
```

```swift
// Start recordings
recorder = IOStreamRecorder()
recorder.delegate = self

// Subscribes stream sample data.
stream.addObserver(recorder)
recorder.startRunning()

// Stop recording.
recorder.stopRunning()
// stream.removeObserver(recorder)
```

### Rename
|1.7.x|1.8.0|
|:-|:-|
|IOStreamDrawable|IOStreamView|
|NetBitRateStrategyConvertible|IOStreamBitRateStrategyConvertible|
|NetBitRateStats|IOStreamBitRateStats|
|NetBitRateStrateg|IOStreamBitRateStrategy|
|VideoAdaptiveNetBitRateStrategy|IOStreamVideoAdaptiveBitRateStrategy|
|IORecorder|IOStreamRecorder|
|IORecorderDelegate|IOStreamRecorderDelegate|
|MultiCamCaptureSettings|IOVideoMixerSettings|
