import AVFoundation
import CoreImage
import Foundation
import Testing

@testable import HaishinKit

@ScreenActor
@Suite struct VideoObjectContainerTests {
    @Test(arguments: [false, true])
    func hdrMixerPreservesSourceColorimetry(hdrInput: Bool) throws {
        var buffer: CVPixelBuffer?
        let format = hdrInput ? kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange : kCVPixelFormatType_32BGRA
        #expect(CVPixelBufferCreate(nil, 64, 64, format, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer) == kCVReturnSuccess)
        let image = try #require(buffer)
        if hdrInput {
            DynamicRangeMode.hdr.attach(image)
        } else {
            CVBufferSetAttachment(image, kCVImageBufferCGColorSpaceKey, CGColorSpace(name: CGColorSpace.sRGB)!, .shouldPropagate)
        }
        #expect(CVPixelBufferLockBaseAddress(image, []) == kCVReturnSuccess)
        if hdrInput {
            for plane in 0..<CVPixelBufferGetPlaneCount(image) {
                let address = try #require(CVPixelBufferGetBaseAddressOfPlane(image, plane))
                let count = CVPixelBufferGetBytesPerRowOfPlane(image, plane) * CVPixelBufferGetHeightOfPlane(image, plane) / 2
                address.assumingMemoryBound(to: UInt16.self).initialize(repeating: (plane == 0 ? 940 : 512) << 6, count: count)
            }
        } else {
            let address = try #require(CVPixelBufferGetBaseAddress(image)).assumingMemoryBound(to: UInt8.self)
            let count = CVPixelBufferGetBytesPerRow(image) * 64
            for offset in stride(from: 0, to: count, by: 4) {
                address[offset] = 224
                address[offset + 1] = 224
                address[offset + 2] = 224
                address[offset + 3] = 255
            }
        }
        #expect(CVPixelBufferUnlockBaseAddress(image, []) == kCVReturnSuccess)
        let reference = linearPixel(image)
        var description: CMVideoFormatDescription?
        #expect(CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: image, formatDescriptionOut: &description) == noErr)
        var sample: CMSampleBuffer?
        var timing = CMSampleTimingInfo(duration: .init(value: 1, timescale: 30), presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        #expect(CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: image, formatDescription: try #require(description), sampleTiming: &timing, sampleBufferOut: &sample) == noErr)
        let screen = Screen()
        screen.size = .init(width: 64, height: 64)
        screen.dynamicRangeMode = .hdr
        screen.append(0, buffer: try #require(sample))
        let result = try #require(screen.makeSampleBuffer(.init(timestamp: 1, targetTimestamp: 1 + 1.0 / 30)))
        let actual = linearPixel(try #require(result.imageBuffer))
        for channel in 0..<3 {
            #expect(abs(actual[channel] - reference[channel]) < 0.03)
        }
        if hdrInput { #expect(actual[0] > 1) }
    }

    private func linearPixel(_ image: CVPixelBuffer) -> [Float] {
        var pixel = [Float](repeating: 0, count: 4)
        CIContext().render(CIImage(cvPixelBuffer: image), toBitmap: &pixel, rowBytes: 16,
                           bounds: CGRect(x: 32, y: 32, width: 1, height: 1), format: .RGBAf,
                           colorSpace: CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020))
        return pixel
    }

    @Test func horizontalAlignmentBounds() {
        let screen = Screen()

        let object1 = VideoScreenObject()
        object1.videoGravity = .resizeAspect
        object1.size = .init(width: 160, height: 90)
        object1.enqueue(CMVideoSampleBufferFactory.makeSampleBuffer(width: 900, height: 1600)!)
        object1.horizontalAlignment = .left

        let object2 = VideoScreenObject()
        object2.videoGravity = .resizeAspect
        object2.size = .init(width: 160, height: 90)
        object2.enqueue(CMVideoSampleBufferFactory.makeSampleBuffer(width: 900, height: 1600)!)
        object2.horizontalAlignment = .center

        let object3 = VideoScreenObject()
        object3.videoGravity = .resizeAspect
        object3.size = .init(width: 160, height: 90)
        object3.enqueue(CMVideoSampleBufferFactory.makeSampleBuffer(width: 900, height: 1600)!)
        object3.horizontalAlignment = .right

        try? screen.addChild(object1)
        try? screen.addChild(object2)
        try? screen.addChild(object3)

        if let sampleBuffer = CMVideoSampleBufferFactory.makeSampleBuffer(width: 1600, height: 900) {
            _ = screen.render(sampleBuffer)
        }

        #expect(object1.bounds == .init(x: 0, y: 0, width: 50.625, height: 90))
        #expect(object2.bounds == .init(x: 774.6875, y: 0, width: 50.625, height: 90))
        #expect(object3.bounds == .init(x: 1549.375, y: 0, width: 50.625, height: 90))
    }
}
