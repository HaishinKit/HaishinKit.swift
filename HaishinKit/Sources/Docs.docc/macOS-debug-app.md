# macOS debug application

Exercise capture, encoding, transport, and playback in the macOS Example app.

## Run the app

Open `Examples/Examples.xcworkspace` and run the `Example macOS` scheme. The
workspace uses the library in the same checkout. Release ZIPs target Apple
Silicon and require macOS 15.5 or later.

## Publish and inspect

Use **Publish** for a camera preview, screen sharing, scene overlay editing,
frame-rate changes, and monochrome effects. **Encoder** controls set the output
resolution, codec, video/audio target bitrates, and hardware encoding for the
next publishing session. **Settings** contains audio format, bitrate mode, and
low-latency options.

New scenes use a 1280 × 720 preview canvas; imported scenes retain their canvas size; encoder output resolution is configured
separately. Target video bitrate is a setting, not a measured throughput value.
Measured TX and send queue use transport reports where the selected protocol
provides them. Output FPS is currently available for RTMP. A dash means a
measurement is unavailable, including before a session starts.

**Share screen or window…** opens the system ScreenCaptureKit picker. Choose a
display, window, or application. Captured video replaces the camera on mixer
track 0; overlays and effects still apply. Audio continues to come from the
microphone when enabled in **Settings → Capture**. Microphone capture is off by
default so video-only debugging does not open an audio device. Camera and
microphone access must be granted before their capture devices are opened.
**Stop sharing · Use camera** restores authorized camera capture. Sharing stops
when the publishing view closes.

## Edit scenes and screen objects

The **Scenes** list stores independent compositions. Its action menu
creates, duplicates, or deletes a scene; enter a name and press Return to rename
it. Selecting another scene changes the preview and the outgoing composition.
Scenes and their layouts are restored the next time the app opens. Edits in another
window are detected before saving; reopen Publish to load the current version if a
conflict is reported. Editing the current scene keeps existing video playback running.

Use **Objects → Add** for capture input, text, an image, or a video file. Capture
input uses the current camera or ScreenCaptureKit source on mixer track 0.
Imported files are copied into scene-specific Application Support `HaishinKit/SceneWorkspaceMedia`
directories so moving the original file does not break the scene. Video objects
loop without supplying audio; microphone settings still control capture audio.

Select an object in the list or preview. Drag it to move, scroll or use the
preview's plus/minus controls to resize, and use **Object inspector** for its
name, position, dimensions, text, font size, and color. Press Return or Apply
to commit inspector edits. The top object in the list is drawn in front; use
the arrows to change its order, the eye to hide it, and the duplicate or trash
buttons to copy or remove it. The last scene cannot be deleted.

Use **Scenes → Export scene file…** to save the current layout and media as a
single `.haishinscene` file. **Open scene file…**, or opening the file in Finder,
restores it as a scene. Autosaved snapshots live in `HaishinKit/Scenes`; existing
preferences are migrated on first launch. Camera/device permissions and network
credentials are not part of a scene. Unsupported objects remain in the file and
are invisible on platforms that cannot render them. See <doc:scene-files>.

## Receive SRT on the local network

In **Playback**, enter a receive port and choose **Listen for SRT sender**.
After the SRT socket is listening, the app announces a Bonjour service:

- Type: `_srt._udp.` in `local.`
- Port: the selected SRT port.
- TXT: `role=receiver`, `version=1`.

The sending client resolves the service address and connects using
`srt://<resolved-host>:<port>?mode=caller`, sending MPEG-TS with supported
video/audio codecs. One sender is accepted per listener. The announcement is
removed once a sender connects or listening stops. Choose **Cancel receiving**
to stop waiting, or **Stop playback** to close an established connection.

For a local smoke test, start listening on port 9000 and send a generated test
pattern with FFmpeg built with SRT support:

```sh
ffmpeg -re -f lavfi -i testsrc2=size=640x360:rate=30 \
  -f lavfi -i sine=frequency=440:sample_rate=48000 \
  -c:v libx264 -preset ultrafast -tune zerolatency -pix_fmt yuv420p \
  -c:a aac -f mpegts 'srt://127.0.0.1:9000?mode=caller'
```

**Find Bonjour services** searches for `_srt._udp` sources and connects in
caller/playback mode. Receiver-only advertisements are excluded from the source
list. Bonjour discovery is an opt-in convention used by this example; arbitrary
SRT servers do not automatically advertise themselves. Local network access
must be allowed, and both peers must be on a network that permits mDNS and SRT.

## Debug tools and HTTP signaling

**Debug** provides verbose library logging and a publish-view sheet for repeated
open/dismiss memory-release checks with Instruments. Debug logs can contain
endpoint URLs and signaling data.

The WHIP/WHEP presets construct client endpoints for a separately running
MediaMTX server. WHIP selects Opus audio. MediaMTX setup and WebRTC network
requirements are documented in the [MediaMTX reference](https://mediamtx.org/docs/features/publish-and-read).
The example permits plain HTTP to support local test servers; configure secure
transport and authentication separately for production applications.
