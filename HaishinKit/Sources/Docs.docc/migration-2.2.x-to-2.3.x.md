# Moving from 2.2.x APIs to 2.3.x

Update session types and screen rendering code for the upcoming 2.3.x release.

## Overview

This guide is based on the changes between the `2.2.5` tag and `main` at commit `18180831`. At the time of writing, 2.3.x has not been released. The changes below describe the current implementation and should be reviewed against the final release before upgrading a production application.

The main source changes affect applications that use the Session API or offscreen video mixing. Applications using `RTMPConnection` / `RTMPStream` or `SRTConnection` / `SRTStream` directly can continue using those APIs.

| Area | Required action |
| --- | --- |
| Session API | Rename the shared `Session` types to `StreamSession` types. |
| Camera overlays | Replace `VideoTrackScreenObject` with `VideoScreenObject`. |
| Image overlays | Replace `ImageScreenObject.cgImage` with `ciImage`. |
| Renderer selection | Remove assignments to `Screen.isGPURendererEnabled`. |
| Custom screen objects | Return `CIImage` from `makeImage(_:)` and update overridden initializers. |
| Raw offscreen output | Handle bi-planar YCbCr buffers instead of assuming packed ARGB. |
| Session URLs | Supply an absolute URL with a scheme and host, except for SRT listener URLs. |
| visionOS applications | Raise the minimum deployment target to visionOS 1.3. |

### Rename the Session API

The shared session types have been renamed. There are no compatibility aliases for the old names.

| 2.2.x | 2.3.x |
| --- | --- |
| `Session` | `StreamSession` |
| `SessionMode` | `StreamSessionMode` |
| `SessionReadyState` | `StreamSessionReadyState` |
| `SessionBuilder` | `StreamSessionBuilder` |
| `SessionBuilderFactory` | `StreamSessionBuilderFactory` |
| `SessionFactory` | `StreamSessionFactory` |
| `SessionConfiguration` | `StreamSessionConfiguration` |

Update stored properties, function signatures, protocol conformances, and references to `SessionBuilderFactory.Error` as well as calls to the builder.

The concrete factories keep their names: `RTMPSessionFactory`, `SRTSessionFactory`, and `HTTPSessionFactory`. `HTTPSessionConfiguration` also keeps its name, but now conforms to `StreamSessionConfiguration`.

#### 2.2.x

```swift
import Foundation
import HaishinKit
import RTMPHaishinKit

func makePublishingSession() async throws -> (any Session)? {
    await SessionBuilderFactory.shared.register(RTMPSessionFactory())
    return try await SessionBuilderFactory.shared
        .make(URL(string: "rtmp://localhost/live/stream"))
        .setMode(.publish)
        .build()
}
```

#### 2.3.x

```swift
import Foundation
import HaishinKit
import RTMPHaishinKit

func makePublishingSession() async throws -> (any StreamSession)? {
    await StreamSessionBuilderFactory.shared.register(RTMPSessionFactory())
    return try await StreamSessionBuilderFactory.shared
        .make(URL(string: "rtmp://localhost/live/stream"))
        .setMode(.publish)
        .build()
}
```

`build()` still returns an optional session and can throw. Keep the existing optional handling and error handling. The `.publish` / `.playback` modes, factory registration, and connection workflow are unchanged.

If you provide a custom session factory, update its `make(_:mode:configuration:)` signature to accept `StreamSessionMode` and `(any StreamSessionConfiguration)?`, and return `any StreamSession`. Custom sessions must expose `AsyncStream<StreamSessionReadyState>` and use the renamed types in their initializer.

### Rename VideoTrackScreenObject

Use `VideoScreenObject` for a camera-track overlay. Its `track`, size, alignment, layout margins, corner radius, and video-effect APIs retain their roles. The track number must still match the track passed to `MediaMixer.attachVideo(_:track:)`.

Both examples run on `ScreenActor`, as required by the screen APIs.

#### 2.2.x

```swift
import HaishinKit

@ScreenActor
func makeCameraOverlay() -> VideoTrackScreenObject {
    let overlay = VideoTrackScreenObject()
    overlay.track = 1
    overlay.size = .init(width: 320, height: 180)
    overlay.horizontalAlignment = .right
    overlay.layoutMargin = .init(top: 16, left: 0, bottom: 0, right: 16)
    return overlay
}
```

#### 2.3.x

```swift
import HaishinKit

@ScreenActor
func makeCameraOverlay() -> VideoScreenObject {
    let overlay = VideoScreenObject()
    overlay.track = 1
    overlay.size = .init(width: 320, height: 180)
    overlay.horizontalAlignment = .right
    overlay.layoutMargin = .init(top: 16, left: 0, bottom: 0, right: 16)
    return overlay
}
```

### Replace CGImage overlays with CIImage overlays

`ImageScreenObject.cgImage` has been replaced with `ciImage`. Convert an existing `CGImage` with `CIImage(cgImage:)`, or supply a `CIImage` directly.

#### 2.2.x

```swift
import CoreGraphics
import HaishinKit

@ScreenActor
func makeImageOverlay(_ image: CGImage) -> ImageScreenObject {
    let overlay = ImageScreenObject()
    overlay.cgImage = image
    overlay.size = .init(width: image.width, height: image.height)
    return overlay
}
```

#### 2.3.x

```swift
import CoreImage
import HaishinKit

@ScreenActor
func makeImageOverlay(_ image: CGImage) -> ImageScreenObject {
    let overlay = ImageScreenObject()
    overlay.ciImage = CIImage(cgImage: image)
    overlay.size = .init(width: image.width, height: image.height)
    return overlay
}
```

### Remove the renderer switch

Offscreen rendering now uses the Core Image renderer (`ScreenRendererByGPU`). The separate CPU renderer and `Screen.isGPURendererEnabled` have been removed. No replacement flag is required; remove both `true` and `false` assignments to this property.

For example, remove this configuration used in 2.2.1 and later:

```swift
@ScreenActor
func configureRenderer(_ screen: Screen) {
    screen.isGPURendererEnabled = true
}
```

Keep your existing offscreen mixing configuration, including `VideoMixerSettings.mode = .offscreen` when compositing overlays. Removing the renderer flag does not enable offscreen mixing by itself.

### Update custom ScreenObject subclasses

The `makeImage(_:) -> CGImage?` overload has been removed. Override the `CIImage?` overload instead. If your drawing code still produces a `CGImage`, wrap the result in `CIImage(cgImage:)` before returning it.

The base initializer is now `init(id: String? = nil)`. Calls such as `ScreenObject()` and `super.init()` still work because the argument has a default. However, a subclass that overrides `init()` must update that override to the new signature, or remove `override` if it intentionally defines a separate zero-argument initializer.

#### 2.2.x

```swift
import CoreGraphics
import HaishinKit

@ScreenActor
final class LogoScreenObject: ScreenObject {
    var image: CGImage? {
        didSet { invalidateLayout() }
    }

    override init() {
        super.init()
        size = .init(width: 128, height: 128)
    }

    override func makeImage(_ renderer: some ScreenRenderer) -> CGImage? {
        return image
    }
}
```

#### 2.3.x

```swift
import CoreImage
import HaishinKit

@ScreenActor
final class LogoScreenObject: ScreenObject {
    var image: CGImage? {
        didSet { invalidateLayout() }
    }

    override init(id: String? = nil) {
        super.init(id: id)
        size = .init(width: 128, height: 128)
    }

    override func makeImage(_ renderer: some ScreenRenderer) -> CIImage? {
        return image.map { CIImage(cgImage: $0) }
    }
}
```

Screen objects now have an immutable `id`. If omitted, a UUID string is generated. You can supply a stable identifier and find the object later with `Screen.findById(_:)` or `ScreenObjectContainer.findById(_:)`. Keep identifiers unique within a screen. Existing applications do not need to adopt explicit identifiers to keep using overlays.

### Check the offscreen output pixel format

For SDR, the pixel buffers allocated by `Screen` change from `kCVPixelFormatType_32ARGB` to `kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange`. HDR uses `kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange`.

If a custom mixer output, recorder, or image-processing step reads the offscreen pixel buffer directly, check `CVPixelBufferGetPixelFormatType(_:)`. Do not assume a single plane or four bytes per pixel. Use the appropriate plane accessors for YCbCr data, or convert to the format your consumer requires. This change concerns buffers produced by offscreen rendering, not a guarantee about every captured or passthrough buffer.

### Validate streaming URLs

`StreamSessionBuilderFactory.make(_:)` now throws `StreamSessionBuilderFactory.Error.illegalArgument` for URLs without a scheme or host, and for an empty host on non-SRT URLs. Use an absolute URL such as `rtmp://localhost/live/stream`, rather than a relative path or a host-only string. A valid URL with no registered protocol factory still fails with `.notFound` when building the session.

SRT listener URLs with an empty host, such as `srt://:9710?mode=listener`, remain supported. SRT caller URLs should specify the remote host. RTMP connection validation also rejects an empty host, and HTTP sessions reject invalid HTTP/HTTPS endpoints before creating a peer connection.

### Update package and platform requirements

The minimum visionOS deployment version increases from 1.0 to 1.3. The other declared minimums remain iOS 15, tvOS 15, Mac Catalyst 15, and macOS 12. The package still declares Swift tools version 6.0.

SRT and WebRTC now obtain their binary frameworks through the `libsrt-xcframework` and `libdatachannel-xcframework` Swift packages, with minimum dependency versions 1.5.7 and 0.24.6 respectively. Previously, the root package declared direct binary targets for libsrt 1.5.4 and libdatachannel 0.24.0. Resolve package dependencies again after updating, and review any application-level pins to the older dependencies. The `SRTHaishinKit` and `RTCHaishinKit` product and import names are unchanged.

SRT address resolution now supports IPv6 as well as IPv4. Existing IPv4 callers do not need a new API. If you use an IPv6 listener, configure the local `adapter` explicitly; the default local adapter is still `0.0.0.0`. For example, `srt://:9710?mode=listener&adapter=::` selects an IPv6 wildcard address.

### Verify the migration

After applying the changes:

1. Build each application target to find references to the removed names and overridden initializers.
2. Exercise session creation, publish/playback, and reconnection with your actual endpoint URLs.
3. Check image overlays, camera overlays, custom drawing, and any consumers of raw offscreen pixel buffers.
4. Test SRT caller/listener behavior for the address families and adapters used by your application.

### Reference

The API changes in this draft were checked against the [source comparison from 2.2.5 to 18180831](https://github.com/HaishinKit/HaishinKit.swift/compare/2.2.5...181808311f5e89572a4de5c67de4ce34cede89cf). Changes made after that commit are not covered by this draft.
