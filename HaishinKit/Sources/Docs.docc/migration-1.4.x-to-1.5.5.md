# Moving from 1.4.x APIs to 1.5.5

Update code written for HaishinKit 1.4.x to use the 1.5.5 APIs.

## Overview

This is a historical migration guide. Code examples refer to the versions shown in each section and may not match the current release.

### VideoSettings
#### 1.4.0
```swift
stream.videoSettings = [
    .width: 640, // video output width
    .height: 360, // video output height
    .bitrate: 160 * 1000, // video output bitrate
    .profileLevel: kVTProfileLevel_H264_Baseline_3_1, // H264 Profile require "import VideoToolbox"
    .maxKeyFrameIntervalDuration: 2, // key frame / sec
]

stream.videoSettings[.bitrate] = 160 * 1000
```

#### 1.5.0
```swift
stream.videoSettings = VideoCodecSettings(
  videoSize: .init(width: 854, height: 480),
  profileLevel: kVTProfileLevel_H264_Baseline_3_1 as String,
  bitRate: 640 * 1000,
  maxKeyFrameIntervalDuration: 2,
  scalingMode: .trim,
  bitRateMode: .average,
  allowFrameReordering: nil,
  isHardwareEncoderEnabled: true
)

stream.videoSettings.bitRate = 640 * 1000
```

### AudioSettings
#### 1.4.0
```swift
rtmpStream.audioSettings = [
    .bitrate: 32 * 1000,
]
```

#### 1.5.0
```swift
stream.audioSettings = AudioCodecSettings(
  bitRate: 64 * 1000,
  format: .aac
)
```

### RTMPStreamDelegate
#### 1.4.0
```swift
/// The interface a RTMPStream uses to inform its delegate.
public protocol RTMPStreamDelegate: AnyObject {
    /// Tells the receiver to publish insufficient bandwidth occured.
    func rtmpStream(_ stream: RTMPStream, publishInsufficientBWOccured connection: RTMPConnection)
    /// Tells the receiver to publish sufficient bandwidth occured.
    func rtmpStream(_ stream: RTMPStream, publishSufficientBWOccured connection: RTMPConnection)
    /// Tells the receiver to playback an audio packet incoming.
    func rtmpStream(_ stream: RTMPStream, didOutput audio: AVAudioBuffer, presentationTimeStamp: CMTime)
    /// Tells the receiver to playback a video packet incoming.
    func rtmpStream(_ stream: RTMPStream, didOutput video: CMSampleBuffer)
    /// Tells the receiver to update statistics.
    func rtmpStream(_ stream: RTMPStream, updatedStats connection: RTMPConnection)
    #if os(iOS)
    /// Tells the receiver to session was interrupted.
    func rtmpStream(_ stream: RTMPStream, sessionWasInterrupted session: AVCaptureSession, reason: AVCaptureSession.InterruptionReason)
    /// Tells the receiver to session interrupted ended.
    func rtmpStream(_ stream: RTMPStream, sessionInterruptionEnded session: AVCaptureSession, reason: AVCaptureSession.InterruptionReason)
    #endif
    /// Tells the receiver to video codec error occured.
    func rtmpStream(_ stream: RTMPStream, videoCodecErrorOccurred error: VideoCodec.Error)
    /// Tells the receiver to the stream opend.
    func rtmpStreamDidClear(_ stream: RTMPStream)
}
```

#### 1.5.0
```swift
/// The interface a RTMPConnectionDelegate uses to inform its delegate.
public protocol RTMPConnectionDelegate: AnyObject {
    /// Tells the receiver to publish insufficient bandwidth occured.
    func connection(_ connection: RTMPConnection, publishInsufficientBWOccured stream: RTMPStream)
    /// Tells the receiver to publish sufficient bandwidth occured.
    func connection(_ connection: RTMPConnection, publishSufficientBWOccured stream: RTMPStream)
    /// Tells the receiver to update statistics.
    func connection(_ connection: RTMPConnection, updateStats stream: RTMPStream)
}

/// The interface a NetStream uses to inform its delegate.
public protocol NetStreamDelegate: AnyObject {
    /// Tells the receiver to playback an audio packet incoming.
    func stream(_ stream: NetStream, didOutput audio: AVAudioBuffer, presentationTimeStamp: CMTime)
    /// Tells the receiver to playback a video packet incoming.
    func stream(_ stream: NetStream, didOutput video: CMSampleBuffer)
    #if os(iOS)
    /// Tells the receiver to session was interrupted.
    func stream(_ stream: NetStream, sessionWasInterrupted session: AVCaptureSession, reason: AVCaptureSession.InterruptionReason)
    /// Tells the receiver to session interrupted ended.
    func stream(_ stream: NetStream, sessionInterruptionEnded session: AVCaptureSession, reason: AVCaptureSession.InterruptionReason)
    #endif
    /// Tells the receiver to video codec error occured.
    func stream(_ stream: NetStream, videoCodecErrorOccurred error: VideoCodec.Error)
    /// Tells the receiver to audio codec error occured.
    func stream(_ stream: NetStream, audioCodecErrorOccurred error: AudioCodec.Error)
    /// Tells the receiver to will drop video frame.
    func streamWillDropFrame(_ stream: NetStream) -> Bool
    /// Tells the receiver to the stream opened.
    func streamDidOpen(_ stream: NetStream)
}
```

### Socket Engine
Changed socket class NSInputStream or NSOutputStream to Network.framework.
If any issues occur, please set `rtmpConnection.requireNetworkFramework` to false.
