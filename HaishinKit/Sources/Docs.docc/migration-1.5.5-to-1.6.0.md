# Moving from 1.5.5 APIs to 1.6.0

Update code written for HaishinKit 1.5.5 to use the 1.6.0 APIs.

## Overview

This is a historical migration guide. Code examples refer to the versions shown in each section and may not match the current release.

I have switched development to Xcode 15. Consequently, the supported iOS and tvOS versions will be 12.0 and later.

### RTMPStream
#### 1.5.5
```swift
open class RTMPStream:: AnyObject {
   open func createMetaData() -> ASObject
}
```

#### 1.6.0
```swift
open class RTMPStream:: AnyObject {
   open func makeMetaData() -> ASObject
}
```

### VideoCodecSettings
#### 1.5.5
```swift
struct VideoCodecSettings: Codable {
    /// Specifies the video size of encoding video.
    public var videoSize: VideoSize
}
```

#### 1.6.0
```swift
struct VideoCodecSettings: Codable {
    /// Specifies the video size of encoding video.
    public var videoSize: CGSize
}
```

### IOUIScreenCaptureUnit
#### 1.5.5
```swift
public class IOUIScreenCaptureUnit: NSObject, IOScreenCaptureUnit {
    public var frameInterval: Int = IOUIScreenCaptureUnit.defaultFrameInterval
}
```

#### 1.6.0
```swift
public class IOUIScreenCaptureUnit: NSObject, IOScreenCaptureUnit {
    public var preferredFramesPerSecond: Int = IOUIScreenCaptureUnit.defaultPreferredFramesPerSecond
}
```
