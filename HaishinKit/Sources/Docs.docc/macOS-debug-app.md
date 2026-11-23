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

The preview canvas is 1280 × 720; encoder output resolution is configured
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
15 fps, limited-range BT.709 reference. It replays those exact pixels through
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
checks payload hashes and ZIP integrity, and retains the packages. In the updated
VQMetrix checkout, run
`VQMETRIX_MACOS_FIXTURES=/tmp/vqmetrix-fixtures swift test --filter actualMacOSProducerArchives`
to validate, decode, and VMAF-evaluate those exact packages.

Run `ruby Examples/Tests/vqmetrix_transfer.rb` to check cancellation before and
during upload, task-registration races, retry IDs, bounded responses, redirects,
and local-network URL validation against temporary local test servers.
