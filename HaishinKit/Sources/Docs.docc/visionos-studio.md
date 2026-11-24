# Using the visionOS sample studio

Receive streams or send a generated test signal from the **Example visionOS** scheme
in `Examples/Examples.xcworkspace`.

## Receive a stream

1. Choose **Receive**, then **Connection**.
2. Enter an RTMP/RTMPS server URL and a stream name, or a complete SRT URL with a port.
3. Close the connection panel and press **Play**. Press **Stop** before changing modes or endpoints.

SRT socket options belong in the URL query. For example, a receiver connecting to
an existing SRT listener can use `srt://192.168.1.10:9710?mode=caller`.
Use the endpoint and socket role expected by the server or peer.

## Broadcast a test signal

1. Choose **Test broadcast**. The idle preview shows the test pattern.
2. Open **Connection** and enter the receiving server/peer's address.
3. Press **Broadcast**. The generated image moves while the connection is active.
4. Press **Stop** to close the connection and stop generating media.

The source is 1280 × 720 at 30 fps, encoded as H.264 at 2.5 Mbps with AAC audio
at 48 kHz / 128 kbps. The stereo test tone is 440 Hz on the left and 880 Hz on
the right. It is sent to the stream, not played through the local speakers.
No camera or microphone is opened and no capture permission is needed.

The simulator requests software video encoding; actual encoder availability and
performance depend on the OS/device. See <doc:codec-support> for capability reports.

## Window controls

The main window separates video from connection controls. **Fill video** in the
lower glass toolbar switches between fitting the complete image and filling the
view (which may crop it). **Device codecs** opens the system capability report,
including its clipboard action.

Connection fields remain in memory for the current window. The selected mode is
remembered between launches. Main-window source labels omit stream keys,
credentials and URL query options. Closing the window stops its session.

## Camera access

This example does not capture the Apple Vision Pro's main camera. Apple's
[main camera access](https://developer.apple.com/documentation/visionos/accessing-the-main-camera)
is an enterprise API requiring a separately approved entitlement. Synthetic test
signals allow publishing to be exercised without that entitlement.
