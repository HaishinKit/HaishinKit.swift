import CoreImage
import Testing

@testable import HaishinKit

@ScreenActor
struct ImageScreenObjectTests {
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
