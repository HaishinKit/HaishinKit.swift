import AVFoundation
import MetalKit
import Testing

@testable import HaishinKit

#if os(iOS) || os(macOS)
@Suite @MainActor struct HDRPlaybackTests {
    @Test func metalViewSwitchesFromHLGToSDR() throws {
        guard #available(iOS 16.0, macOS 12.0, *) else {
            return
        }
        let view = MTHKView(frame: .init(x: 0, y: 0, width: 192, height: 108))
        let metalLayer = try #require(view.layer as? CAMetalLayer)
        view.updateDynamicRange(try makeSample(.hdr))
        #expect(view.colorPixelFormat == .rgba16Float)
        #expect(metalLayer.wantsExtendedDynamicRangeContent)
        #expect(metalLayer.colorspace?.name == CGColorSpace.extendedLinearITUR_2020)
        #expect(metalLayer.edrMetadata != nil)

        view.updateDynamicRange(try makeSample(.sdr))
        #expect(view.colorPixelFormat == .bgra8Unorm)
        #expect(!metalLayer.wantsExtendedDynamicRangeContent)
        #expect(metalLayer.colorspace?.name == CGColorSpace.sRGB)
        #expect(metalLayer.edrMetadata == nil)
    }

    private func makeSample(_ mode: DynamicRangeMode) throws -> CMSampleBuffer {
        var image: CVPixelBuffer?
        #expect(CVPixelBufferCreate(kCFAllocatorDefault, 192, 108, mode.videoFormat, nil, &image) == kCVReturnSuccess)
        let pixelBuffer = try #require(image)
        mode.attach(pixelBuffer)
        var format: CMVideoFormatDescription?
        #expect(CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescriptionOut: &format) == noErr)
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        #expect(CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescription: try #require(format), sampleTiming: &timing, sampleBufferOut: &sample) == noErr)
        return try #require(sample)
    }
}
#endif
