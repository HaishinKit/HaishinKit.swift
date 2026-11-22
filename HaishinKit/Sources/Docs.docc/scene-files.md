# Portable scene files

Save a ScreenObjectSnapshot and its media in one file shared by Apple and Android.

## File format

A `.haishinscene` file is a regular ZIP containing:

- `scene.json`: a camelCase ``ScreenObjectSnapshot`` object, without an envelope.
- `manifest.json`: `{"format":"haishinkit.scene","version":1}`.
- `media/<filename>`: bundled images, video, or resources for future object types.

Readers accept ZIP STORE and DEFLATE entries, including Java ZIP data descriptors.
They also accept standalone snapshot JSON when no external media is needed.
Resource names are flat filenames, unique under the shared conservative case key
(NFC, lowercase, uppercase, lowercase, NFC; Unicode default/ROOT casing); absolute paths and traversal are rejected.
The limits are 128 MiB of resources, 256 resources, and 4 MiB of snapshot JSON.

The snapshot retains `type`, `id`, `size`, `isVisible`, `layoutMargin`, horizontal
and vertical alignment, `elements`, `children`, and optional `cornerRadius`.
Object-specific properties stay in the string-valued `elements` map. Images and
assets reference bundled media with `source: "media/<filename>"`. Inline image
data URLs remain supported. Video gravity values are `resize`, `resizeAspect`,
and `resizeAspectFill`; an omitted value means `resizeAspect`.

## Save and load

```swift
let snapshot = ScreenObjectSnapshotFactory().make(screenObject)
let sceneFile = try SceneFile(snapshot: snapshot, resources: ["overlay.png": imageData])
try sceneFile.encoded().write(to: destination, options: .atomic)
let restored = try SceneFile(data: Data(contentsOf: destination))
```

Before saving, use relative media references, or supply resources named after the
local file URL's last path component; the scene file converts matching image/asset
file URLs to portable references. After loading, materialize resources in app
storage and replace known media references with those local file URLs before
passing the snapshot to ``ScreenObjectFactory``. The scene file does not open
capture devices, request permissions, or restore transport credentials.

## Unsupported objects

An unsupported type produces an invisible placeholder. Snapshot capture returns
its original type, properties, visibility intent, and subtree so another platform
can restore it later. Do not discard opaque objects or their bundled resources
when editing or exporting. A saved `isVisible: true` remains true even when the
current platform cannot draw the object. Android currently treats Apple's
`asset` video-file objects this way.

The macOS example uses this format for Open/Export and keeps lightweight snapshot
JSON plus scene-specific media caches for automatic local saves.
