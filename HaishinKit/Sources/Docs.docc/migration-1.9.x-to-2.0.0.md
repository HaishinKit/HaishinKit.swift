# Moving from 1.9.x APIs to 2.0.0

Update code written for HaishinKit 1.9.x to use the 2.0.0 APIs.

## Overview

This is a historical migration guide. Code examples refer to the versions shown in each section and may not match the current release.

### IOStream
I redesigned the system to address the demand for streaming to multiple services. The responsibilities are split into [MediaMixer](https://docs.haishinkit.com/swift/2.0.0/Actors/MediaMixer.html), which handles capture from the device, and [HKStream](https://docs.haishinkit.com/swift/2.0.0/Protocols/HKStream.html), which focuses on live streaming video and audio.

#### Attaching the view

##### 1.9.x
```swift
stream = IOStream()
view = MTHKView()

view.attachStream(stream)
```

##### 2.0.0
```swift
mixer = MediaMixer()
stream = HKStream()
view = MTHKView()
// view2 = MTHKView()

mixer.addOutput(stream)
stream.addOutput(view)
// stream.addOutput(view2)
```
It is possible to set multiple views on the mixer. This allows you to directly monitor the video CMSampleBuffer during capture. You can switch between views by changing the track. Setting track = UInt8.max makes it equivalent to the value being output to HKStream.
```swift
mixer = MediaMixer()
view0 = MTHKView()
view1 = MTHKView()

view0.videoTrackId = 0
view1.videoTrackId = UInt8.max

mixer.addOutput(view0)
mixer.addOutput(view1)
```

#### attachCamera, attachAudio
##### 1.9.x
```swift
stream = IOStream()

stream.attachCamera(AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back), track: 0) { _, error in
  if let error {
    logger.warn(error)
  }
}

stream.attachAudio(AVCaptureDevice.default(for: .audio)) { _, error in
  if let error {
    logger.warn(error)
  }
}
```

```swift
guard
  let device = stream.videoCapture(for: 0)?.device, device.isFocusPointOfInterestSupported else {
  return
}
do {
  try device.lockForConfiguration()
  device.focusPointOfInterest = pointOfInterest
  device.focusMode = .continuousAutoFocus
  device.unlockForConfiguration()
} catch let error as NSError {
  logger.error("while locking device for focusPointOfInterest: \(error)")
            }
```

##### 2.0.x
```swift
mixer = MediaMixer()
stream = RTMPStream() // or SRTStream

do {
  try await mixer.attachVideo(AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back))
} catch {
  logger.warn(error)
}

do {
  try await mixer.attachAudio(AVCaptureDevice.default(for: .audio))
} catch {
  logger.warn(error)
}

mixer.addOutput(stream)
```

```swift
try await mixer.configuration(video: 0) { unit in
  guard let device = unit.device else {
    return
  }
  try device.lockForConfiguration()
  device.focusPointOfInterest = pointOfInterest
  device.focusMode = .continuousAutoFocus
  device.unlockForConfiguration()
}
```

#### Playback
If you want to play audio, please attach a single-instance AudioPlayer. AudioPlayer is a wrapper for AVAudioEngine.
##### 1.9.x
```swift
stream = RTMPStream()

stream.play("streamName")
```

##### 2.0.x
```swift
audioPlayer = AudioPlauer(AVAudioEngine())

stream = RTMPStream()
stream.attachAudioPlayer(audioPlayer)

stream.play("streamName")
```

#### Recording
##### 1.9.x

```swift
stream = RTMPStream()
recorder = IOStreamRecorder()
stream.addObserver(recorder)

recorder.delegate = self
recorder.startRunning()
recorder.stopRunning()

extension IngestViewController: IOStreamRecorderDelegate {
  // MARK: IOStreamRecorderDelegate
  func recorder(_ recorder: IOStreamRecorder, errorOccured error: IOStreamRecorder.Error) {
    logger.error(error)
  }

  func recorder(_ recorder: IOStreamRecorder, finishWriting writer: AVAssetWriter) {
    PHPhotoLibrary.shared().performChanges({() -> Void in
      PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: writer.outputURL)
    }, completionHandler: { _, error -> Void in
      try? FileManager.default.removeItem(at: writer.outputURL)
    })
  }
}
```

##### 2.0.0
```swift
stream = RTMPStream() // or SRTStream()
recorder = HKStreamRecorder()

stream.addOutput(recorder)

do {
  try await recorder.startRecording()
} catch {
  print(error)
}

do {
  let outputURL = try await recorder.stopRecording()
  PHPhotoLibrary.shared().performChanges({() -> Void in
    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: outputURL)
  }, completionHandler: { _, error -> Void in
    try? FileManager.default.removeItem(at: outputURL)
  })
} catch {
  print(error)
}
```

### RTMP

#### Discontinued
- RTMPT, RTMPTS protocols.
  - I decided this because I judged the usage frequency to be low.

#### Signature
Inheritance is no longer possible due to the transition to actors. If you were using inheritance and are now facing issues, please let us know how you were using it, and I can discuss possible solutions.

|1.9.x|2.0.0|
|:-|:-|
|public class RTMPConnection|actor RTMPConnection|
|open class RTMPStream|actor RTMPStream|

#### RTMPConnection
Regarding the specification of detailed properties.

##### 1.9.x
```swift
public actor RTMPConnection {
  /// Specifies the URL of .swf.
  public var swfUrl: String?
  /// Specifies the URL of an HTTP referer.
  public var pageUrl: String?
  /// Specifies the time to wait for TCP/IP Handshake done.
  ...
}
```

##### 2.0.x
The constructor now accepts it as an argument.
```swift
public actor RTMPConnection {
  /// The URL of .swf.
  public let swfUrl: String?
  /// The URL of an HTTP referer.
  public let pageUrl: String?
  /// The name of application.
  public let flashVer: String
  /// The time to wait for TCP/IP Handshake done.
  public let timeout: Int
  /// The RTMP request timeout value. Defaul value is 500 msec.
  public let requestTimeout: UInt64
  /// The outgoing RTMPChunkSize.
  public let chunkSize: Int
  /// The dispatchQos for socket.
  public let qualityOfService: DispatchQoS

  /// Creates a new connection.
  public init(
    swfUrl: String? = nil,
    pageUrl: String? = nil,
    flashVer: String = RTMPConnection.defaultFlashVer,
    timeout: Int = RTMPConnection.defaultTimeout,
    requestTimeout: UInt64 = RTMPConnection.defaultRequestTimeout,
    chunkSize: Int = RTMPConnection.defaultChunkSizeS,
    qualityOfService: DispatchQoS = .userInitiated) {
    self.swfUrl = swfUrl
    self.pageUrl = pageUrl
    self.flashVer = flashVer
    self.timeout = timeout
    self.requestTimeout = requestTimeout
    self.chunkSize = chunkSize
    self.qualityOfService = qualityOfService
  }
}
```

#### EventHandle
##### 1.9.x
Discontinued event handling related to `addEventHandler`.
```swift
connection.addEventListener(.rtmpStatus, selector: #selector(rtmpStatusHandler), observer: self)
connection.addEventListener(.ioError, selector: #selector(rtmpErrorHandler), observer: self)

@objc
private func rtmpStatusHandler(_ notification: Notification) {
  let e = Event.from(notification)
  guard let data: ASObject = e.data as? ASObject, let code: String = data["code"] as? String else {
    return
  }
  logger.info(code)
  switch code {
  case RTMPConnection.Code.connectSuccess.rawValue:
    stream?.publish(Preference.default.streamName!) // or play
  case RTMPConnection.Code.connectFailed.rawValue, RTMPConnection.Code.connectClosed.rawValue:
    connection?.connect(uri)
  default:
    break
  }
}
```

##### 2.0.0
```swift
connection = RTMPConnection()
stream = RTMPStream(connection: connection)

do {
  let response = try await connection.connect(preference.uri ?? "")
  try await stream.publish(Preference.default.streamName) // or play
} catch RTMPConnection.Error.requestFailed(let response) {
  logger.warn(response)
} catch RTMPStream.Error.requestFailed(let response) {
  logger.warn(response)
} catch {
  logger.warn(error)
}
```

#### RTMPConnectionDelegate
##### 1.9.x
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

var connection: RTMPConnect
connection.delegate = self
```

##### 2.0.0
```swift
/// The struct represents a network statistics.
public struct NetworkMonitorReport: Sendable {
    /// The statistics of total incoming bytes.
    public let totalBytesIn: Int
    /// The statistics of total outgoing bytes.
    public let totalBytesOut: Int
    /// The statistics of outgoing queue bytes per second.
    public let currentQueueBytesOut: Int
    /// The statistics of incoming bytes per second.
    public let currentBytesInPerSecond: Int
    /// The statistics of outgoing bytes per second.
    public let currentBytesOutPerSecond: Int
}

/// A type with a network bitrate strategy representation.
public protocol HKStreamBitRateStrategy: Sendable {
  /// The mamimum video bitRate.
  var mamimumVideoBitRate: Int { get }
  /// The mamimum audio bitRate.
  var mamimumAudioBitRate: Int { get }

  /// Adjust a bitRate.
  func adjustBitrate(_ event: NetworkMonitorEvent, stream: some HKStream) async
}

/// An enumeration that indicate the network monitor event.
public enum NetworkMonitorEvent: Sendable {
  /// To update statistics.
  case status(report: NetworkMonitorReport)
  /// To publish sufficient bandwidth occured.
  case publishInsufficientBWOccured(report: NetworkMonitorReport)
  /// To reset statistics.
  case reset
}

final final actor MyStreamBitRateStrategy: HKStreamBitRateStrategy {
  func adjustBitrate(_ event: NetworkMonitorEvent, stream: some HKStream) async {
  }
}

var stream: (any HKStream)
var strategy = MyStreamBitRateStrategy()
async stream.setBitrateStrategy(strategy)
```

### SRT
#### Signature
|1.9.x|2.0.0|
|:-|:-|
|public class SRTConnection|actor SRTConnection|
|final class SRTStream|actor SRTStream|

### Others
#### Discontinued
- Support [Carthage](https://github.com/Carthage/Carthage).

#### ASClass
|1.9.x|2.0.0|
|:-|:-|
|ASObject|AMFObject|
|ASUndefined|AMFUndefined|
|ASTypedObject|AMFTypedObject|
|ASArray|AMFArray|
|ASXMLDocument|AMFXMLDocument|
|ASXMLDocument|AMFXMLDocument|
|ASXML|AMFXML|

#### KVO
With the main classes becoming actors, KVO with @objc is no longer possible. It has been changed to the @Published property wrapper.

##### 1.9.x
```swift
private var keyValueObservations: [NSKeyValueObservation] = []

let keyValueObservation = connection.observe(\.connected, options: [.new,
.old]) { [weak self] _, _ in
  guard let self = self else {
    return
  }
  if connection.connected {
    // do something
  } else {
    // do something
  }
}

keyValueObservations.append(keyValueObservation)
```

##### 2.0.0
```swift
private var cancellables: Set<AnyCancellable> = []

await connection.$connected.sink {
 print("receive: \($0)") }
.store(in: &cancellables)
```

#### Others
- Flutter Plugin migration example:
  - https://github.com/HaishinKit/HaishinKit.dart/pull/67
