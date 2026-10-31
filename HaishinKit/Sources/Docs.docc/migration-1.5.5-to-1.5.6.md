# Moving from 1.5.5 APIs to 1.5.6

Update code written for HaishinKit 1.5.5 to use the 1.5.6 APIs.

## Overview

This is a historical migration guide. Code examples refer to the versions shown in each section and may not match the current release.

### RTMPStreamDelegate
#### 1.5.5
```swift
/// The interface a RTMPStream uses to inform its delegate.
public protocol RTMPStreamDelegate: AnyObject {
    #if os(iOS)
    /// Tells the receiver to session was interrupted.
    func rtmpStream(_ stream: RTMPStream, sessionWasInterrupted session: AVCaptureSession, reason: AVCaptureSession.InterruptionReason)
    /// Tells the receiver to session interrupted ended.
    func rtmpStream(_ stream: RTMPStream, sessionInterruptionEnded session: AVCaptureSession, reason: AVCaptureSession.InterruptionReason)
    #endif
}
```

#### 1.5.6
```swift
/// The interface a NetStream uses to inform its delegate.
public protocol NetStreamDelegate: AnyObject {
    #if os(iOS)
    /// Tells the receiver to session was interrupted.
    func stream(_ stream: NetStream, sessionWasInterrupted session: AVCaptureSession, reason: AVCaptureSession.InterruptionReason?)
    /// Tells the receiver to session interrupted ended.
    func stream(_ stream: NetStream, sessionInterruptionEnded session: AVCaptureSession)
    #endif
}
```
