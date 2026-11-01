import AVFoundation
import Foundation
import Testing

@testable import HaishinKit

@ScreenActor
@Suite struct ScreenObjectSnapshotTests {
    @Test func videoSnapshot() throws {
        let string = """
{"type":"video","id":"1771162233189358-1238207813","size":{"width":90,"height":160},"isVisible":true,"layoutMargin":{"top":16,"left":0,"bottom":0,"right":16},"horizontalAlignment":2,"verticalAlignment":0,"elements":{"track":"1"},"children":[]}
""".data(using: .utf8)!
        let snapshot = try JSONDecoder().decode(ScreenObjectSnapshot.self, from: string)
        #expect(snapshot.type == "video")
        #expect(snapshot.horizontalAlignment == 2)
        #expect(snapshot.verticalAlignment == 0)
    }
}

@ScreenActor
@Suite struct ScreenObjectSnapshotCompatibilityTests {
    private func fixture() throws -> ScreenObjectSnapshot {
        let url = try #require(Bundle.module.url(forResource: "screen_object_snapshot", withExtension: "json"))
        return try JSONDecoder().decode(ScreenObjectSnapshot.self, from: Data(contentsOf: url))
    }

    private func json(_ snapshot: ScreenObjectSnapshot) throws -> NSDictionary {
        try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? NSDictionary)
    }

    @Test func sharedWireFormatRoundTrip() throws {
        let snapshot = try fixture()
        let decoded = try JSONDecoder().decode(ScreenObjectSnapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(try json(decoded) == json(snapshot))
        #expect(snapshot.children[1].children[0].elements["value"] == "字幕 🎥\nHaishinKit")
    }

    @Test func restoresHierarchyAndAllCommonProperties() throws {
        let snapshot = try fixture()
        let object = try #require(ScreenObjectFactory().make(snapshot) as? ScreenObjectContainer)
        #expect(object.children.map(\.id) == ["camera", "overlay"])
        let overlay = try #require(object.findById("overlay") as? ScreenObjectContainer)
        #expect(overlay.parent === object)
        #expect(overlay.children.map(\.id) == ["caption", "logo"])
        let video = try #require(object.findById("camera") as? VideoScreenObject)
        #expect(video.track == 1)
        let text = try #require(object.findById("caption") as? TextScreenObject)
        #expect(text.elements["fontSize"] == "24.5")
        #expect(text.elements["color"] == "#8044AAFF")
        let image = try #require(object.findById("logo") as? ImageScreenObject)
        #expect(image.ciImage != nil)
        #expect(try json(ScreenObjectSnapshotFactory().make(object)) == json(snapshot))
    }

    @Test func capturesConcreteTypes() throws {
        let objects: [ScreenObject] = [VideoScreenObject(), TextScreenObject(), ImageScreenObject(), ScreenObjectContainer()]
        #expect(objects.map { ScreenObjectSnapshotFactory().make($0).type } == ["video", "text", "image", "container"])
    }

    @Test func restoresAndroidScreenAsContainer() throws {
        let data = try JSONEncoder().encode(fixture())
        var value = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        value["type"] = "screen"
        let snapshot = try JSONDecoder().decode(ScreenObjectSnapshot.self, from: JSONSerialization.data(withJSONObject: value))
        let object = try #require(ScreenObjectFactory().make(snapshot) as? ScreenObjectContainer)
        #expect(object.childCounts == 2)
        #expect(object.id == "root")
    }

    @Test func restoredVideoAlignmentSurvivesActorSuspension() async throws {
        let snapshot = try fixture().children[0]
        let video = try #require(ScreenObjectFactory().make(snapshot) as? VideoScreenObject)
        // The initializer must not schedule a later reset of restored alignment.
        try await Task.sleep(for: .milliseconds(20))
        #expect(video.horizontalAlignment == .right)
        #expect(video.isVisible == false)
    }
}
