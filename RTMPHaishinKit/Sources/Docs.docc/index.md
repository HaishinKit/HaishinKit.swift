# ``RTMPHaishinKit``
This module supports the RTMP protocol.

@Metadata {
    @PageImage(purpose: icon, source: "rtmphaishinkit-icon.svg", alt: "Live broadcasting")
    @PageImage(purpose: card, source: "rtmphaishinkit-card.svg", alt: "Live broadcasting")
}

## 🔍 Overview
RTMPHaishinKit is RTMP protocols stack in Swift. 

## 🎨 Features
- [x] FMLE-compatible Authentication
- [x] Publish
  - H264, HEVC, AAC and OPUS support.
- [x] Playback
  - H264, HEVC and AAC support.
- [ ] Action Message Format
  - [x] AMF0
  - [ ] AMF3
- [x] SharedObject
- [x] RTMPS
  - [x] Native (RTMP over SSL/TLS)
- [x] [Enhanced RTMP](E-RTMP.md)

## 📓 Usage
### Publish
```swift
let mixer = MediaMixer()
let connection = RTMPConnection()
let stream = RTMPStream(connection: connection)
let hkView = MTHKView(frame: view.bounds)

Task {
  do {
    try await mixer.attachAudio(AVCaptureDevice.default(for: .audio))
  } catch {
    print(error)
  }

  do {
    try await mixer.attachVideo(AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back))
  } catch {
    print(error)
  }

  await mixer.addOutput(stream)
}

Task { MainActor in
  await stream.addOutput(hkView)
  // add ViewController#view
  view.addSubview(hkView)
}

Task {
  do {
    try await connection.connect("rtmp://localhost/appName/instanceName")
    try await stream.publish(streamName)
  } catch RTMPConnection.Error.requestFailed(let response) {
    print(response)
  } catch RTMPStream.Error.requestFailed(let response) {
    print(response)
  } catch {
    print(error)
  }
}
```

### Playback
```swift
let connection = RTMPConnection()
let stream = RTMPStream(connection: connection)
let audioPlayer = AudioPlayer(AVAudioEngine())

let hkView = MTHKView(frame: view.bounds)

Task { MainActor in
  await stream.addOutput(hkView)
}

Task {
  // requires attachAudioPlayer
  await stream.attachAudioPlayer(audioPlayer)

  do {
    try await connection.connect("rtmp://localhost/appName/instanceName")
    try await stream.play(streamName)
  } catch RTMPConnection.Error.requestFailed(let response) {
    print(response)
  } catch RTMPStream.Error.requestFailed(let response) {
    print(response)
  } catch {
    print(error)
  }
}
```

### Authentication
It supports FME-compatible authentication. Some other services may use their own unique authentication methods, so connection may not be possible in those cases.
```swift
var connection = RTMPConnection()
connection.connect("rtmp://username:password@localhost/appName/instanceName")
```

