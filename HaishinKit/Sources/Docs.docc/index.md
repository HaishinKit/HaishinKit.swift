# ``HaishinKit``
This is the main module.

## 🔍 Overview
Provides camera and microphone mixing functionality required for live streaming.  
It also offers common processing across each module.

### Module Structure
| Module | Description |
|:-|:-|
| HaishinKit | This module. |
| RTMPHaishinKit | Provides the RTMP protocol stack. |
| SRTHaishinKit | Provides the SRT protocol stack. |
| RTCHaishinKit | Provides the WebRTC WHEP/WHIP protocol stack. Currently in alpha. |
| MoQTHaishinKit | Provides the MoQT protocol stack. Currently in alpha. |

## 🎨 Features
The following features are available:
- Live Mixing
  - [Video Mixing](doc://HaishinKit/videomixing)  
    - Treats camera video and still images as a single stream source.  
  - Audio Mixing  
    - Combines different microphone audio sources into a single audio stream source.  
- Session  
  - Provides a unified API for protocols such as RTMP, SRT, WHEP, and WHIP.  

## 📖 Usage
### Live Mixing
```swift
let mixer = MediaMixer()

Task {
  do {
    // Attaches the microphone device.
    try await mixer.attachAudio(AVCaptureDevice.default(for: .audio))
  } catch {
    print(error)
  }

  do {
    // Attaches the camera device.
    try await mixer.attachVideo(AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back))
  } catch {
    print(error)
  }

  // Associates the stream object with the MediaMixer.
  await mixer.addOutput(stream)
  await mixer.startRunning()
}
```

### StreamSession API
Provides a unified API for implementing clients with RTMP and SRT. Retry handling is also performed internally by the API.

#### Preparation
```swift
import HaishinKit
import RTMPHaishinKit
import SRTHaishinKit

Task {
  await StreamSessionBuilderFactory.shared.register(RTMPSessionFactory())
  await StreamSessionBuilderFactory.shared.register(SRTSessionFactory())
}
```

#### Make StreamSession
**RTMP**
Please provide the RTMP connection URL combined with the streamName.
```swift
let session = try await StreamSessionBuilderFactory.shared.make(URL(string: "rtmp://hostname/appName/stramName"))
  .setMode(.publish)
  .build()
```
**SRT**
```swift
let session = try await StreamSessionBuilderFactory.shared.make(URL(string: "srt://hostname:448?stream=xxxxx"))
  .setMode(.playback)
  .build()
```

#### Connecting
Used for publishing or playback.
```swift
try session.connect {
  print("on disconnected")
}
```

