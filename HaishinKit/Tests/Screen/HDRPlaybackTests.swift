import Accelerate
import AVFoundation
import MetalKit
import Testing

@testable import HaishinKit

#if os(iOS) || os(macOS)
@Suite @MainActor struct HDRPlaybackTests {
    @Test(arguments: [false, true])
    func metalViewSwitchesFromHLGToSDR(customSDRConfiguration: Bool) throws {
        guard #available(iOS 16.0, macOS 12.0, *) else {
            return
        }
        let view = MTHKView(frame: .init(x: 0, y: 0, width: 192, height: 108))
        let metalLayer = try #require(view.layer as? CAMetalLayer)
        if customSDRConfiguration {
            view.colorPixelFormat = .bgra8Unorm_srgb
            metalLayer.colorspace = CGColorSpace(name: CGColorSpace.displayP3)
            metalLayer.wantsExtendedDynamicRangeContent = true
            metalLayer.edrMetadata = .hlg
        }
        let originalPixelFormat = view.colorPixelFormat
        let originalColorSpace = metalLayer.colorspace
        let originalWantsEDR = metalLayer.wantsExtendedDynamicRangeContent
        let originalMetadata = metalLayer.edrMetadata
        #expect(view.dynamicRangeMode == .sdr)
        view.setDynamicRangeMode(.hdr)
        view.setDynamicRangeMode(.hdr)
        #expect(view.dynamicRangeMode == .hdr)
        #expect(view.colorPixelFormat == .rgba16Float)
        #expect(metalLayer.wantsExtendedDynamicRangeContent)
        #expect(metalLayer.colorspace?.name == CGColorSpace.extendedLinearITUR_2020)
        #expect(metalLayer.edrMetadata == nil)

        view.setDynamicRangeMode(.sdr)
        #expect(view.dynamicRangeMode == .sdr)
        #expect(view.colorPixelFormat == originalPixelFormat)
        #expect(metalLayer.wantsExtendedDynamicRangeContent == originalWantsEDR)
        #expect(metalLayer.colorspace?.name == originalColorSpace?.name)
        #expect(metalLayer.edrMetadata === originalMetadata)
    }

    @Test(.enabled(if: MTLCreateSystemDefaultDevice() != nil, "Requires Metal"), arguments: [UInt16(502), 721, 940])
    func metalDestinationPreservesHDRLuminance(luma: UInt16) throws {
        guard #available(iOS 16.0, macOS 12.0, *) else {
            return
        }
        let sample = try makeSample(.hdr)
        let image = try #require(sample.imageBuffer)
        #expect(CVPixelBufferLockBaseAddress(image, []) == kCVReturnSuccess)
        for plane in 0..<CVPixelBufferGetPlaneCount(image) {
            let address = try #require(CVPixelBufferGetBaseAddressOfPlane(image, plane))
            let count = CVPixelBufferGetBytesPerRowOfPlane(image, plane) * CVPixelBufferGetHeightOfPlane(image, plane) / 2
            address.assumingMemoryBound(to: UInt16.self).initialize(repeating: (plane == 0 ? luma : 512) << 6, count: count)
        }
        #expect(CVPixelBufferUnlockBaseAddress(image, []) == kCVReturnSuccess)
        let input = CIImage(cvPixelBuffer: image)
        let expected = referenceLinearPixel(input)
        let view = MTHKView(frame: .init(x: 0, y: 0, width: 192, height: 108))
        view.setDynamicRangeMode(.hdr)
        let pixel = try renderPixel(input, in: view)
        for channel in 0..<3 {
            #expect(abs(pixel[channel] - expected[channel]) < 0.02)
        }
        if luma == 940 {
            #expect(pixel[0] > 1)
        }
    }

    @Test(.enabled(if: MTLCreateSystemDefaultDevice() != nil, "Requires Metal"))
    func sdrAssetRetainsBrightnessInHDRPreview() async throws {
        guard #available(iOS 16.0, macOS 12.0, *) else { return }
        let (sample, expected) = try await AssetHDRReference.makeSample()
        let image = CIImage(cvPixelBuffer: try #require(sample.imageBuffer))
        let view = MTHKView(frame: image.extent)
        view.setDynamicRangeMode(.hdr)
        let pixel = try renderPixel(image, in: view)
        for channel in 0..<3 {
            #expect(abs(pixel[channel] - expected[channel]) < 0.025)
        }
    }

    private func referenceLinearPixel(_ image: CIImage) -> [Float] {
        var pixel = [Float](repeating: 0, count: 4)
        CIContext().render(image, toBitmap: &pixel, rowBytes: 16,
                           bounds: CGRect(x: image.extent.midX, y: image.extent.midY, width: 1, height: 1),
                           format: .RGBAf, colorSpace: CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020))
        return pixel
    }

    private func renderPixel(_ image: CIImage, in view: MTHKView) throws -> [Float] {
        let layer = try #require(view.layer as? CAMetalLayer)
        let device = try #require(view.device)
        let queue = try #require(device.makeCommandQueue())
        let command = try #require(queue.makeCommandBuffer())
        let width = Int(image.extent.width), height = Int(image.extent.height)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: view.colorPixelFormat, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        descriptor.storageMode = .private
        let texture = try #require(device.makeTexture(descriptor: descriptor))
        let readback = try #require(device.makeBuffer(length: 256, options: .storageModeShared))
        let destination = CIRenderDestination(width: width, height: height, pixelFormat: view.colorPixelFormat, commandBuffer: command, mtlTextureProvider: { texture })
        destination.colorSpace = try #require(layer.colorspace)
        let context = CIContext(mtlDevice: device, options: [.workingFormat: CIFormat.RGBAh.rawValue])
        let task = try context.startTask(toRender: image, to: destination)
        let blit = try #require(command.makeBlitCommandEncoder())
        blit.copy(
            from: texture, sourceSlice: 0, sourceLevel: 0,
            sourceOrigin: .init(x: width / 2, y: height / 2, z: 0), sourceSize: .init(width: 1, height: 1, depth: 1),
            to: readback, destinationOffset: 0, destinationBytesPerRow: 256, destinationBytesPerImage: 256
        )
        blit.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        _ = try task.waitUntilCompleted()
        var source = vImage_Buffer(data: readback.contents(), height: 1, width: 4, rowBytes: 8)
        var pixel = [Float](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { bytes in
            var output = vImage_Buffer(data: bytes.baseAddress!, height: 1, width: 4, rowBytes: 16)
            #expect(vImageConvert_Planar16FtoPlanarF(&source, &output, vImage_Flags(kvImageNoFlags)) == kvImageNoError)
        }
        return pixel
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

@ScreenActor private enum AssetHDRReference {
    static func makeSample() throws -> (CMSampleBuffer, [Float]) {
        let url = try #require(Bundle.module.url(forResource: "SampleVideo_360x240_5mb", withExtension: "mp4"))
        let asset = AssetScreenObject()
        try asset.startReading(AVURLAsset(url: url))
        defer { asset.cancelReading() }
        asset.bounds = CGRect(x: 0, y: 0, width: 360, height: 240)
        let input = try #require(asset.makeImage(ScreenRendererByGPU(dynamicRangeMode: .sdr)))
        var expected = [Float](repeating: 0, count: 4)
        CIContext().render(input, toBitmap: &expected, rowBytes: 16,
                           bounds: CGRect(x: 180, y: 120, width: 1, height: 1),
                           format: .RGBAf, colorSpace: CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020))
        let screen = Screen()
        screen.size = .init(width: 360, height: 240)
        screen.dynamicRangeMode = .hdr
        try screen.addChild(asset)
        let sample = try #require(screen.makeSampleBuffer(.init(timestamp: 1, targetTimestamp: 1 + 1.0 / 30)))
        return (sample, expected)
    }
}
#endif

@Suite @ScreenActor struct ScreenHDRTests {
    @Test func offscreenSamplesCarryHLGFormatDescription() throws {
        let screen = Screen()
        screen.size = .init(width: 192, height: 108)
        screen.dynamicRangeMode = .hdr
        var retainedSamples: [CMSampleBuffer] = []
        for index in 1...6 {
            let sample = try #require(screen.makeSampleBuffer(.init(timestamp: Double(index), targetTimestamp: Double(index) + 1.0 / 30)))
            let format = try #require(sample.formatDescription)
            let image = try #require(sample.imageBuffer)
            #expect(format.isHDR)
            #expect(CMVideoFormatDescriptionMatchesImageBuffer(format, imageBuffer: image))
            #expect(CMFormatDescriptionGetExtension(format, extensionKey: kCMFormatDescriptionExtension_ColorPrimaries) as? String == kCMFormatDescriptionColorPrimaries_ITU_R_2020 as String)
            #expect(CMFormatDescriptionGetExtension(format, extensionKey: kCMFormatDescriptionExtension_YCbCrMatrix) as? String == kCMFormatDescriptionYCbCrMatrix_ITU_R_2020 as String)
            retainedSamples.append(sample)
            if index == 3 {
                retainedSamples.removeAll()
            }
        }
        screen.dynamicRangeMode = .sdr
        let sdr = try #require(screen.makeSampleBuffer(.init(timestamp: 7, targetTimestamp: 7 + 1.0 / 30)))
        #expect(sdr.formatDescription?.isHDR == false)
    }
}
