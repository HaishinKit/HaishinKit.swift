# Moving from 1.6.x APIs to 1.7.0

Update code written for HaishinKit 1.6.x to use the 1.7.0 APIs.

## Overview

This is a historical migration guide. Code examples refer to the versions shown in each section and may not match the current release.

### NetStream
#### 1.6.x
```swift
open class NetStream: NSObject {
    public var loopback: Bool { get set }
    public func appendSampleBuffer(_ sampleBuffer: CMSampleBuffer)
}
```

#### 1.7.0
```swift
open class NetStream: NSObject {
   public var isMonitoringEnabled: Bool { get set }
   public func append(_ sampleBuffer: CMSampleBuffer)
}
```
### Recording
#### 1.6.x
```swift
stream.mixer.recorder.isRuning

stream.mixer.recorder.delegate = self
stream.startRecording(settings)
```

#### 1.7.1
```swift
stream.isRecording
stream.startRecording(self, settings: settings)
```

### NetStreamDelegate
#### 1.6.x
```swift
/// The interface a NetStream uses to inform its delegate.
public protocol NetStreamDelegate: AnyObject {
    /// Tells the receiver to video error occured.
    func stream(_ stream: NetStream, videoErrorOccurred error: AudioCodec.Error)
    /// Tells the receiver to audio error occured.
    func stream(_ stream: NetStream, audioErrorOccurred error: VideoCodec.Error)
}
```

#### 1.7.0
```swift
/// The interface a NetStream uses to inform its delegate.
public protocol NetStreamDelegate: AnyObject {
    /// Tells the receiver to video error occured.
    func stream(_ stream: NetStream, videoErrorOccurred error: IOVideoUnitError)
    /// Tells the receiver to audio error occured.
    func stream(_ stream: NetStream, audioErrorOccurred error: IOAudioUnitError)
}
```

### AudioEffect
#### 1.6.x
```swift
/// An object that apply an audio effect.
open class AudioEffect: NSObject {
    /// Executes to apply an audio effect.
    open func execute(_ buffer: UnsafeMutableAudioBufferListPointer?, format: AudioStreamBasicDescription?) {
    }
}
```

#### 1.7.0
You can get PCM data, so please process it in this delegate.

```swift
/// The interface a NetStream uses to inform its delegate.
public protocol NetStreamDelegate: AnyObject {
    /// Tells the receiver an audio packet incoming.
    func stream(_ stream: NetStream, didOutput audio: AVAudioBuffer, when: AVAudioTime)
}
```
