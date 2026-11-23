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
        #expect(metalLayer.colorspace?.name == CGColorSpace.itur_2100_HLG)
        #expect(metalLayer.edrMetadata == nil)

        view.setDynamicRangeMode(.sdr)
        #expect(view.dynamicRangeMode == .sdr)
        #expect(view.colorPixelFormat == originalPixelFormat)
        #expect(metalLayer.wantsExtendedDynamicRangeContent == originalWantsEDR)
        #expect(metalLayer.colorspace?.name == originalColorSpace?.name)
        #expect(metalLayer.edrMetadata === originalMetadata)
    }

    @Test(.enabled(if: MTLCreateSystemDefaultDevice() != nil, "Requires Metal"), arguments: [UInt16(502), 721, 940])
    func metalDestinationPreservesHLGSignal(luma: UInt16) throws {
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
        let view = MTHKView(frame: .init(x: 0, y: 0, width: 192, height: 108))
        view.setDynamicRangeMode(.hdr)
        let layer = try #require(view.layer as? CAMetalLayer)
        let device = try #require(view.device)
        let queue = try #require(device.makeCommandQueue())
        let command = try #require(queue.makeCommandBuffer())
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: view.colorPixelFormat, width: 192, height: 108, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        descriptor.storageMode = .private
        let texture = try #require(device.makeTexture(descriptor: descriptor))
        let readback = try #require(device.makeBuffer(length: 256, options: .storageModeShared))
        let destination = CIRenderDestination(width: 192, height: 108, pixelFormat: view.colorPixelFormat, commandBuffer: command, mtlTextureProvider: { texture })
        destination.colorSpace = try #require(layer.colorspace)
        let context = CIContext(mtlDevice: device, options: [.workingFormat: CIFormat.RGBAh.rawValue])
        let task = try context.startTask(toRender: CIImage(cvPixelBuffer: image), to: destination)
        let blit = try #require(command.makeBlitCommandEncoder())
        blit.copy(
            from: texture, sourceSlice: 0, sourceLevel: 0,
            sourceOrigin: .init(x: 96, y: 54, z: 0), sourceSize: .init(width: 1, height: 1, depth: 1),
            to: readback, destinationOffset: 0, destinationBytesPerRow: 256, destinationBytesPerImage: 256
        )
        blit.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        _ = try task.waitUntilCompleted()
        let pixel = UnsafeBufferPointer(start: readback.contents().assumingMemoryBound(to: UInt16.self), count: 4)
        // Positive binary16 values are ordered. These encode HLG levels 0.5, 0.75, and 1.0.
        // Compare known bits so this test also compiles on Intel macOS, without Float16.
        let expected: UInt16 = switch luma {
        case 502: 0x3800
        case 721: 0x3a00
        default: 0x3c00
        }
        for channel in pixel.prefix(3) {
            #expect(abs(Int(channel) - Int(expected)) <= 4)
        }
        #expect(layer.edrMetadata == nil)
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
