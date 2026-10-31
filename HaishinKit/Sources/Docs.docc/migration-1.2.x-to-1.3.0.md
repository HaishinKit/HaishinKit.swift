# Moving from 1.2.x APIs to 1.3.0

Update code written for HaishinKit 1.2.x to use the 1.3.0 APIs.

## Overview

This is a historical migration guide. Code examples refer to the versions shown in each section and may not match the current release.

### Recording
#### 1.2.x
```swift
// startRecording
rtmpStream.publish("streamName", .localRecord)

// stopRecording
rtmpStream.publish()
```

#### 1.3.0
- You can record without publishing.
```swift
rtmpStream.mixer.recorder.delegate = self
rtmpStream.startRecording()
rtmpStream.stopRecording()

extension ViewController: AVRecorderDelegate {
    // MARK: AVRecorderDelegate
    func recorder(_ recorder: AVRecorder, errorOccured error: AVRecorder.Error) {
        logger.error(error)
    }

    func recorder(_ recorder: AVRecorder, finishWriting writer: AVAssetWriter) {
        PHPhotoLibrary.shared().performChanges({() -> Void in
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: writer.outputURL)
        }, completionHandler: { _, error -> Void in
            do {
                try FileManager.default.removeItem(at: writer.outputURL)
            } catch {
                print(error)
            }
        })
    }
}
```

### RTMPStreamDelegate
|1.2.x|1.3.0|
|:-|:-|
|func rtmpStream(_ stream: RTMPStream, didPublishInsufficientBW connection: RTMPConnection)|func rtmpStream(_ stream: RTMPStream, publishInsufficientBWOccured connection: RTMPConnection|
|func rtmpStream(_ stream: RTMPStream, didPublishSufficientBW connection: RTMPConnection)|func rtmpStream(_ stream: RTMPStream, publishSufficientBWOccured connection: RTMPConnection)|
|func rtmpStream(_ stream: RTMPStream, didStatics connection: RTMPConnection)|func rtmpStream(_ stream: RTMPStream, updatedStats connection: RTMPConnection)|
