import AVFoundation
import CoreGraphics
import Testing

@testable import HaishinKit

@ScreenActor
struct ScreenObjectEditorTests {
    @Test func previewCoordinatesRespectCroppingLetterboxAndStretch() throws {
        let screen = CGSize(width: 1280, height: 720)
        let preview = CGSize(width: 640, height: 480)
        let fit = try #require(ScreenCoordinateTransform(screenSize: screen, previewSize: preview))
        #expect(fit.toScreen(.zero as CGPoint) == CGPoint(x: 0, y: -120))
        let fill = try #require(ScreenCoordinateTransform(screenSize: screen, previewSize: preview, videoGravity: .resizeAspectFill))
        #expect(abs(fill.toScreen(.zero as CGPoint).x - 160) < 0.001)
        let stretch = try #require(ScreenCoordinateTransform(screenSize: screen, previewSize: preview, videoGravity: .resize))
        #expect(stretch.toPreview(CGRect(origin: .zero, size: screen)) == CGRect(origin: .zero, size: preview))
        #expect(ScreenCoordinateTransform(screenSize: .zero, previewSize: preview) == nil)
    }

    @Test func hitTestingFollowsDrawingOrderAndSceneMembership() throws {
        let screen = Screen()
        let editor = ScreenObjectEditor(screen: screen)
        let back = ScreenObject()
        let front = ScreenObject()
        try screen.addChild(back)
        try screen.addChild(front)
        screen.videoTrackScreenObject.bounds = CGRect(origin: .zero, size: screen.size)
        back.bounds = CGRect(x: 10, y: 10, width: 100, height: 100)
        front.bounds = back.bounds
        let point = CGPoint(x: 20, y: 20)
        #expect(editor.hitTest(point) === front)
        front.isVisible = false
        #expect(editor.hitTest(point) === back)
        screen.removeChild(back)
        #expect(editor.hitTest(point) == nil)
    }

    @Test func transformKeepsTheAnchorAndAppliesSizeLimitsBeforeLayout() throws {
        let screen = Screen()
        let editor = ScreenObjectEditor(screen: screen)
        let object = ScreenObject()
        try screen.addChild(object)
        object.size = CGSize(width: 100, height: 50)
        let initial = CGRect(x: 200, y: 100, width: 100, height: 50)
        let anchor = CGPoint(x: 250, y: 125)
        let next = try #require(editor.transform(
            object, bounds: initial, anchor: anchor, destination: CGPoint(x: 300, y: 200), scale: 2
        ))
        #expect(next == CGRect(x: 200, y: 150, width: 200, height: 100))
        let clamped = try #require(editor.transform(object, bounds: next, anchor: anchor, destination: CGPoint(x: -20, y: -20), scale: 0.01))
        #expect(clamped.size == CGSize(width: 48, height: 24))
        #expect(clamped.origin == .zero)
        #expect(object.size == clamped.size)
        screen.removeChild(object)
        #expect(editor.transform(object, bounds: clamped, anchor: anchor, destination: anchor) == nil)
    }
}
