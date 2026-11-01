# ``RTCHaishinKit``
This module supports WHIP/WHEP protocols.

@Metadata {
    @PageImage(purpose: icon, source: "rtchaishinkit-icon.svg", alt: "Real-time two-way communication")
    @PageImage(purpose: card, source: "rtchaishinkit-card.svg", alt: "Real-time two-way communication")
}

## 🔍 Overview
RTCHaishinKit is WHIP/WHEP protocols stack in Swift. It internally uses a library that is built from [libdatachannel](https://github.com/paullouisageneau/libdatachannel) and converted into an xcframework.

## 🎨 Features
- Publish(WHIP)
  - H264 and OPUS support.
- Playback(WHEP)
  - H264 and OPUS support.

## 📓 Usage
### Logging
- Defining a Swift wrapper method for `rtcInitLogger`.
```swift
await RTCLogger.shared.setLevel(.debug)
```

### Session
Currently designed to work with the Session API.
```swift
import RTCHaishinKit

await SessionBuilderFactory.shared.register(HTTPSessionFactory())
```

