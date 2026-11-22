# 📺 HaishinKit for Apple TV

A remote-friendly SRT debugging app with video preview, audio level, frame/buffer counts, bitrate, RTT, and packet loss.

## 🛠 Run

Open `Examples/Examples.xcworkspace`, select **Example tvOS**, and run on tvOS 17 or later. The library's deployment requirements are unchanged.

Test signals work in Simulator. Continuity Camera requires a supported Apple TV 4K (2nd generation or later) and an iPhone or iPad running iOS/iPadOS 17 or later. Camera and microphone access must be allowed. Validate camera capture on physical devices.

## 📡 Receive and send

- **Receive → Listener:** start listening, then select this Apple TV in another HaishinKit sample's Bonjour receivers.
- **Send → Caller:** start a receiver on another device, find it on Bonjour, select it, and connect.
- Reverse the connection direction with **Send → Listener** or **Receive → Caller**. Manual `srt://host:port` URLs are also supported.
- Switch between moving 720p30 color bars with stereo tones (left 440 Hz, right 880 Hz) and Continuity Camera while stopped. Choose the camera device before connecting.

Keep both devices on the same local network and allow Local Network access. Listeners advertise `_srt._udp` with `role=receiver` or `role=source` and `version=1`. Announcements stop when a peer connects or listening stops. Each listener accepts one peer at a time.

## 🎛 Controls

Use the Siri Remote to navigate, mute audio, change the video bitrate while stopped, or enter full screen. Back returns from full screen. Backgrounding stops connections and capture; return to reconnect. **Settings** retains the existing playback and connection settings screens.

[API reference](https://docs.haishinkit.com/swift/)

## 🌐 RTMP and WebRTC

Select **RTMP** for publishing or playback with a complete `rtmp://host/app/stream` URL (RTMPS is also supported). Select **WebRTC** for **Send / WHIP** or **Receive / WHEP**, using the full HTTP(S) endpoint. WebRTC uses H.264 and Opus; RTMP and SRT use H.264 and AAC. The sample allows local HTTP resources while preserving ATS for remote hosts.

**Use local test server** fills a MediaMTX endpoint. Run MediaMTX separately and use the server's LAN address on physical devices. The preview, source selector, mute, error messages, and media inspector apply to every protocol. SRT additionally shows measured throughput, RTT, and packet loss; RTMP playback shows receive throughput. WebRTC reports connection and decoded media delivery, rather than estimated network statistics.

## 📊 VQMetrix

While stopped on **Send**, select a working video source and choose **Evaluate in VQMetrix**. Enable Receive in the VQMetrix Mac app, select the discovered Mac, and enter its current 4-digit code. The code is not saved.

The app captures 45 frames at 640 × 360 / 15 fps, converts them to a common limited-range BT.709 reference, and replays those exact pixels through H.264 at 0.5, 1 and 2 Mbps. A protocol-v1 ZIP includes the Y4M reference, MP4 variants, frame maps and SHA-256 checksums. This measures the app's normalized encoder input, rather than raw camera sensor output. Audio is excluded.

An acceptance receipt means the Mac queued the package; view History there for VMAF results. A failed upload can retry the same package and run ID. Local HTTP is restricted to resolved LAN addresses, redirects are disabled, and HTTPS uses system certificate validation. Temporary package files are removed after acceptance or replacement.

When multiple network interfaces interfere with WebRTC, set the optional **ICE bind address**. For localhost tests in Simulator, `0.0.0.0` selects IPv4. On physical devices, use the device's own interface address or leave this blank for automatic selection.
