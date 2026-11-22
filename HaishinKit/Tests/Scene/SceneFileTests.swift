import AVFoundation
import Foundation
import Testing

@testable import HaishinKit

@Suite struct SceneFileTests {
    private func snapshot() -> ScreenObjectSnapshot {
        .init(
            type: "container", id: "scene", size: .init(width: 1280, height: 720),
            children: [
                .init(
                    type: "android.custom", id: "foreign", size: .init(width: 120, height: 80),
                    elements: ["source": "media/opaque.bin", "custom": "preserve me"])
            ])
    }

    @Test func portableArchiveKeepsSnapshotAndOpaqueResources() throws {
        let original = try SceneFile(snapshot: snapshot(), resources: ["opaque.bin": Data([0, 1, 2, 3])])
        let encoded = try original.encoded()
        #expect(encoded.prefix(4) == Data([0x50, 0x4b, 0x03, 0x04]))
        let restored = try SceneFile(data: encoded)
        #expect(restored.resources == original.resources)
        #expect(restored.snapshot.children[0].elements == original.snapshot.children[0].elements)
        #expect(restored.snapshot.children[0].type == "android.custom")
    }

    @Test func rejectsCorruptAndTruncatedArchives() throws {
        let encoded = try SceneFile(snapshot: snapshot()).encoded()
        #expect(throws: (any Error).self) { try SceneFile(data: Data(encoded.dropLast())) }
        var corrupted = encoded
        // Alter a stored file payload while preserving the central directory and its CRC.
        let marker = try #require(corrupted.range(of: Data("haishinkit.scene".utf8)))
        corrupted[marker.lowerBound] ^= 1
        #expect(throws: (any Error).self) { try SceneFile(data: corrupted) }
    }

    @Test func rejectsResourcePathTraversal() {
        for name in ["../escape", "/absolute", "a/b", "a\\b", ".."] {
            #expect(throws: (any Error).self) { try SceneFile(snapshot: snapshot(), resources: [name: Data()]) }
        }
    }

    @Test func acceptsStandaloneSharedJSON() throws {
        let restored = try SceneFile(data: JSONEncoder().encode(snapshot()))
        #expect(restored.snapshot.id == "scene")
        #expect(restored.resources.isEmpty)
    }

    @ScreenActor @Test func unsupportedNodeIsInvisibleWithoutLosingItsSnapshot() throws {
        let original = snapshot().children[0]
        let object = try #require(ScreenObjectFactory().make(original))
        #expect(!object.isVisible)
        let restored = ScreenObjectSnapshotFactory().make(object)
        #expect(restored.type == original.type)
        #expect(restored.isVisible == true)
        #expect(restored.elements == original.elements)
    }

    @ScreenActor @Test func capturesCornerRadiusAndVideoGravity() throws {
        let object = VideoScreenObject(id: "camera")
        object.cornerRadius = 12.5
        object.videoGravity = .resizeAspectFill
        let snapshot = ScreenObjectSnapshotFactory().make(object)
        let restored = try #require(ScreenObjectFactory().make(snapshot) as? VideoScreenObject)
        #expect(restored.cornerRadius == 12.5)
        #expect(restored.videoGravity == .resizeAspectFill)
    }

    @Test func readsJavaDeflateArchive() throws {
        let url = try #require(Bundle.module.url(forResource: "java_scene_deflate", withExtension: "zip"))
        let restored = try SceneFile(data: Data(contentsOf: url))
        #expect(restored.snapshot.id == "android-fixture")
        #expect(restored.resources["shared.bin"] == Data([1, 2, 3, 4]))
    }

    @Test func readsArchiveWrittenByAndroidSceneFile() throws {
        let url = try #require(Bundle.module.url(forResource: "android_scene_deflate", withExtension: "haishinscene"))
        let restored = try SceneFile(data: Data(contentsOf: url))
        #expect(restored.snapshot.id == "root")
        #expect(restored.snapshot.children[1].children[0].elements["value"] == "字幕 🎥\nHaishinKit")
        #expect(restored.resources["movie.bin"] == Data([0, 1, 2, 3]))
    }

    @Test func rejectsOversizedDeclaredOutputBeforeDecompression() throws {
        var encoded = try SceneFile(snapshot: snapshot()).encoded()
        let central = try #require(encoded.range(of: Data([0x50, 0x4b, 0x01, 0x02])))
        for offset in 24..<28 { encoded[central.lowerBound + offset] = 0xff }
        #expect(throws: (any Error).self) { try SceneFile(data: encoded) }
    }

    @ScreenActor @Test func unsupportedSubtreeKeepsChildrenAndTheirPlatformFields() throws {
        let original = ScreenObjectSnapshot(
            type: "android.mask", id: "mask", size: .init(width: 300, height: 200),
            elements: ["mask": "media/mask.bin"], children: [snapshot().children[0]])
        let root = try #require(ScreenObjectFactory().make(original))
        #expect(!root.isVisible)
        let captured = ScreenObjectSnapshotFactory().make(root)
        #expect(captured.type == "android.mask")
        #expect(captured.children[0].elements == original.children[0].elements)
        #expect(captured.elements["mask"] == "media/mask.bin")
    }

    #if !os(visionOS)
    @ScreenActor @Test func assetSourceSurvivesSnapshotReconstruction() throws {
        let source = try #require(Bundle.module.url(forResource: "SampleVideo_360x240_5mb", withExtension: "mp4"))
        let video = AssetScreenObject(id: "movie")
        defer { video.cancelReading() }
        video.isLooping = true
        video.videoGravity = .resizeAspectFill
        try video.startReading(AVURLAsset(url: source))
        let snapshot = ScreenObjectSnapshotFactory().make(video)
        #expect(snapshot.type == "asset")
        let restored = try #require(ScreenObjectFactory().make(snapshot) as? AssetScreenObject)
        defer { restored.cancelReading() }
        #expect(restored.isReading)
        #expect(restored.isLooping)
        #expect(restored.videoGravity == .resizeAspectFill)
        #expect(restored.elements["source"] == source.absoluteString)
    }

    #endif

    @ScreenActor @Test func fileImageSourceSurvivesSnapshotReconstruction() throws {
        let fixture = try #require(Bundle.module.url(forResource: "screen_object_snapshot", withExtension: "json"))
        let snapshot = try JSONDecoder().decode(ScreenObjectSnapshot.self, from: Data(contentsOf: fixture))
        let encoded = try #require(snapshot.children[1].children[1].elements["source"]?.components(separatedBy: "base64,").last)
        let png = try #require(Data(base64Encoded: encoded))
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
        try png.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let image = ImageScreenObject(id: "file-image")
        image.elements = ["source": file.absoluteString]
        let restored = try #require(ScreenObjectFactory().make(ScreenObjectSnapshotFactory().make(image)) as? ImageScreenObject)
        #expect(restored.ciImage != nil)
        #expect(restored.elements["source"] == file.absoluteString)
        let archive = try SceneFile(snapshot: ScreenObjectSnapshotFactory().make(image), resources: [file.lastPathComponent: png])
        #expect(archive.snapshot.elements["source"] == "media/" + file.lastPathComponent)
        #expect(try SceneFile(data: archive.encoded()).resources[file.lastPathComponent] == png)
    }

    @Test func stretchUsesIndependentCanvasDimensions() {
        let transform = AVLayerVideoGravity.resize.scale(CGSize(width: 200, height: 150), image: CGSize(width: 100, height: 50))
        #expect(transform.a == 2)
        #expect(transform.d == 3)
    }
    @Test func rejectsCaseAndUnicodeEquivalentResourceNames() throws {
        #expect(throws: (any Error).self) {
            try SceneFile(snapshot: snapshot(), resources: ["Logo.png": Data([1]), "logo.png": Data([2])])
        }
        #expect(throws: (any Error).self) {
            try SceneFile(snapshot: snapshot(), resources: ["İ.png": Data([1]), "i\u{307}.png": Data([2])])
        }
    }

    @Test func rejectsCaseFoldingAliases() throws {
        #expect(throws: (any Error).self) {
            try SceneFile(snapshot: snapshot(), resources: ["Messages.png": Data([1]), "Meſſages.png": Data([2])])
        }
    }

    @Test func rejectsSharedConservativeCaseAliases() throws {
        #expect(throws: (any Error).self) {
            try SceneFile(snapshot: snapshot(), resources: ["I.png": Data([1]), "ı.png": Data([2])])
        }
    }

}
