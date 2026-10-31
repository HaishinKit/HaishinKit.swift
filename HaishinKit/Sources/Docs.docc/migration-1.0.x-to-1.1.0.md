# Moving from 1.0.x APIs to 1.1.0

Update code written for HaishinKit 1.0.x to use the 1.1.0 APIs.

## Overview

This is a historical migration guide. Code examples refer to the versions shown in each section and may not match the current release.

### RTMPStreamDelegate

|1.0.x|1.1.0|
|:-|:-|
|func didPublishInsufficientBW(_ stream: RTMPStream, withConnection: RTMPConnection)|func rtmpStream(_ stream: RTMPStream, didPublishInsufficientBW connection: RTMPConnection)|
|func didPublishSufficientBW(_ stream: RTMPStream, withConnection: RTMPConnection)|func rtmpStream(_ stream: RTMPStream, didPublishSufficientBW connection: RTMPConnection)|
|func didOutputAudio(_ buffer: AVAudioPCMBuffer, presentationTimeStamp: CMTime)|func rtmpStream(_ stream: RTMPStream, didOutput audio: AVAudioBuffer, presentationTimeStamp: CMTime)|
|func didOutputVideo(_ buffer: CMSampleBuffer)|func rtmpStream(_ stream: RTMPStream, didOutput video: CMSampleBuffer)|
|func didStatics(_ stream: RTMPStream, withConneciton: RTMPConnection)|func rtmpStream(_ stream: RTMPStream, didStatics connection: RTMPConnection)|
|func clear()|func rtmpStreamClear()|
