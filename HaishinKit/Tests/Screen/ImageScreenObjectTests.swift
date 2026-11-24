import AVFoundation
import CoreImage
import Testing

@testable import HaishinKit

@ScreenActor
struct ImageScreenObjectTests {
    @Test(arguments: [false, true])
    func imageRemainsVisibleWhenSwitchingDynamicRange(nested: Bool) throws {
        let screen = Screen()
        screen.size = .init(width: 64, height: 64)
        let image = ImageScreenObject()
        image.ciImage = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))
        if nested {
            let group = ScreenObjectContainer()
            try group.addChild(image)
            try screen.addChild(group)
        } else {
            try screen.addChild(image)
        }
        let modes: [DynamicRangeMode] = [.sdr, .hdr, .sdr, .hdr]
        for (index, mode) in modes.enumerated() {
            screen.dynamicRangeMode = mode
            let sample = try #require(screen.makeSampleBuffer(.init(timestamp: Double(index + 1), targetTimestamp: Double(index + 1) + 1.0 / 30)))
            let pixel = try #require(sample.imageBuffer)
            #expect(image.isVisible)
            #expect(CVPixelBufferLockBaseAddress(pixel, .readOnly) == kCVReturnSuccess)
            let address = try #require(CVPixelBufferGetBaseAddressOfPlane(pixel, 0))
            let luma = mode == .hdr ? Int(address.assumingMemoryBound(to: UInt16.self).pointee >> 6) : Int(address.assumingMemoryBound(to: UInt8.self).pointee)
            #expect(luma > (mode == .hdr ? 512 : 128))
            #expect(CVPixelBufferUnlockBaseAddress(pixel, .readOnly) == kCVReturnSuccess)
        }
    }

    @Test func deletingAnOverlayReleasesTheCachedObject() throws {
        let screen = Screen()
        weak var deleted: ImageScreenObject?
        do {
            let overlay = ImageScreenObject()
            deleted = overlay
            overlay.ciImage = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 20, height: 20))
            overlay.bounds = CGRect(x: 0, y: 0, width: 20, height: 20)
            try screen.addChild(overlay)
            screen.renderer.layout(overlay)
            screen.removeChild(overlay)
        }
        #expect(deleted == nil)
    }

    @Test func scalesAndClipsInObjectCoordinates() throws {
        let image = ImageScreenObject()
        image.ciImage = CIImage(color: .white).cropped(to: CGRect(x: 20, y: 30, width: 200, height: 100))
        let renderer = ScreenRendererByGPU(dynamicRangeMode: .sdr)
        renderer.bounds = CGRect(x: 0, y: 0, width: 100, height: 100)

        image.bounds = CGRect(x: 20, y: 30, width: 40, height: 20)
        let scaled = try #require(image.makeImage(renderer))
        #expect(scaled.extent == CGRect(x: 0, y: 0, width: 40, height: 20))

        image.bounds = CGRect(x: -10, y: 90, width: 40, height: 20)
        let clipped = try #require(image.makeImage(renderer))
        #expect(clipped.extent == CGRect(x: 10, y: 10, width: 30, height: 10))

        image.bounds = CGRect(x: 100, y: 100, width: 40, height: 20)
        #expect(image.makeImage(renderer) == nil)
    }
}
