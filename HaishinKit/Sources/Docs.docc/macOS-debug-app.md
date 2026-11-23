# macOS debug application

Exercise capture, encoding, transport, and playback in the macOS Example app.

## Run the app

Open `Examples/Examples.xcworkspace` and run the `Example macOS` scheme. The
workspace uses the library in the same checkout. Release ZIPs target Apple
Silicon and require macOS 15.5 or later.

The interface supports English and Japanese and follows the system's per-app
language preference.

## Publish and inspect

Use **Publish** for a camera preview, screen sharing, scene overlay editing,
frame-rate changes, and monochrome effects. **Encoder** controls set the output
resolution, codec, video/audio target bitrates, and hardware encoding for the
next publishing session. **Settings** contains audio format, bitrate mode, and
low-latency options.

For HDR publishing, enable **Video → Mixer HDR (HLG)** and select
**Encoder → Video codec → HEVC Main10 (HDR)** before going live. The mixer
switch controls 10-bit HLG scene mixing and preview; native camera HDR capture
depends on the device. The encoder choice selects the HEVC Main10 profile for
the next stream. The app shows a configuration message and disables **Go live**
when the mixer and encoder dynamic ranges differ. Enhanced RTMP HDR also
requires a compatible server and player. Both controls are locked during a
broadcast; HDR can be previewed while disconnected.

Both **Publish** and **Playback** offer **MTHKView** (Metal) and
**PiPView** (sample-buffer display) below the preview. With either renderer,
**Open floating preview** shows a resizable, always-on-top video window.
Changing the renderer updates both the inline preview and the open floating
window, retaining the window's size and position. Closing the window leaves
the inline preview running without restarting capture or the connection. The floating window shows only video,
not scene editing handles. It closes when leaving the screen.

This is an application-managed floating window. System Picture in Picture
for sample-buffer display layers is currently unavailable on macOS; see the
[framework support clarification](https://developer.apple.com/forums/thread/830764).

New scenes use a 1280 × 720 preview canvas; imported scenes retain their canvas size; encoder output resolution is configured
separately. Target video bitrate is a setting, not a measured throughput value.
Use **MediaMixer** to choose a canvas preset or apply a custom width and height
(1–8192 pixels), and set the compositor FPS separately from the capture-input FPS.
Canvas dimensions are saved with the scene. Overlays keep their coordinates;
full-canvas capture objects follow the new dimensions. The encoder resolution
remains independent. The tinted area around the preview is outside the video
canvas and is not sent to the stream.

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

Use **Objects → Add** for capture input, a video-only test signal, text, an image,
or a video file. The test signal is a shared example ScreenObject with color bars,
a moving marker, and a frame counter. Its `testSignal` snapshot node is saved
with the scene; readers without this example type retain it invisibly. Capture
input uses the current camera or ScreenCaptureKit source on mixer track 0.
Imported files are copied into scene-specific Application Support `HaishinKit/SceneWorkspaceMedia`
directories so moving the original file does not break the scene. Video objects
loop without supplying audio; microphone settings still control capture audio.

Images retain their source aspect ratio, including previously stretched image
objects. Editing either image dimension adjusts the other proportionally. Turn off
**Keep image aspect ratio** in the inspector to test stretched image layouts.

Select an object in the list or preview. Drag it to move, scroll or use the
selection's bottom-right handle to resize, and use **Object inspector** for its
name, position, dimensions, text, font size, and color. Press Return or Apply
to commit inspector edits. The top object in the list is drawn in front; use
the arrows to change its order, the eye to hide it, and the duplicate or trash
buttons to copy or remove it. The last scene cannot be deleted.

Use **Scenes → Export scene file…** to save the current layout and media as a
single `.scene` file. **Open scene file…**, or opening the file in Finder,
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

## Upload a VQMetrix comparison

In **Publish → VQMetrix**, choose **Capture preview sample** while the preview is
running. The app captures 45 composed frames, normalized to a 640 × 360,
15 fps, limited-range BT.709 reference. Capture spacing uses a monotonic arrival
clock; source timestamps do not control the sampling interval. It replays those exact pixels through
an offline encoder using **Evaluation codec** and the **Encoder** video bitrate. Resolution,
frame rate, codec, and hardware selection in the live encoder controls do not apply to
this offline encoder. Audio is excluded, and this comparison does not measure
network effects or the exact live encoded bitstream.

Start **Receive** in VQMetrix, enter its base URL (for example,
`http://127.0.0.1:8787`) and current four-digit connection code, then choose
**Upload sample**. HTTP is intended for a trusted network and transmits the
video and connection code without encryption. HTTP accepts private, link-local,
or loopback IP addresses and `.local` names only. The app validates all resolved
addresses for a `.local` name and sends to a validated address. HTTPS keeps the
original hostname and uses system certificate validation. Redirects are rejected.

The app submits a `vqmetrix.capture.v1` ZIP with the raw Y4M reference, encoded
variant, frame map, and SHA-256 manifest. H.264/HEVC use MP4; AV1 uses
libaom, and VP8/VP9 use libvpx, stored in IVF. The software codecs require
Apple silicon and a VQMetrix receiver with IVF upload support. A successful upload displays the accepted
job ID; evaluation results are available in VQMetrix. Failed uploads retain the
same package and run ID for retry. Capturing another sample replaces the previous
package; temporary files are removed when the panel is released. The connection
code is not persisted.

### Verify the producer

On Apple silicon, run `ruby Examples/Tests/vqmetrix_capture.rb /tmp/vqmetrix-fixtures`
with a new output directory. This feeds deterministic frames through the actual
capture/package implementation for all five codecs without opening a camera,
checks 15 fps sampling of 60 Hz arrivals with mismatched source timestamps,
payload hashes and ZIP integrity, and retains the packages. In the updated
VQMetrix checkout, run
`VQMETRIX_MACOS_FIXTURES=/tmp/vqmetrix-fixtures swift test --filter actualMacOSProducerArchives`
to validate, decode, and VMAF-evaluate those exact packages.

Run `ruby Examples/Tests/vqmetrix_transfer.rb` to check cancellation before and
during upload, task-registration races, retry IDs, bounded responses, redirects,
and local-network URL validation against temporary local test servers.

## Updates and licenses

Choose **HaishinKit → Check for Updates…** to check GitHub Releases, or configure
automatic checks and downloads under **Settings → App updates**. Installation
uses signed update files; restart after finishing any active debug session.
The first release containing this updater requires a manual installation.

**Configuration → Licenses** contains searchable, selectable license text and
source-availability notices for the components used by the app. These notices
are available offline and follow the dependencies resolved for that build.
