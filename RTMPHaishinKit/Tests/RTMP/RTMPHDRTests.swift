import AVFoundation
import Foundation
import Testing
import VideoToolbox

@testable import HaishinKit
@testable import RTMPHaishinKit

@Suite struct RTMPHDRTests {
    @Test func sdrVideoRoundTrip() async throws {
        try await videoRoundTrip(hdr: false, codedFramesX: false)
    }

    @Test(.enabled(if: Self.supportsHEVCHardwareEncoding, "Requires HEVC hardware encoding"), arguments: [false, true])
    func hlgVideoRoundTrip(codedFramesX: Bool) async throws {
        try await videoRoundTrip(hdr: true, codedFramesX: codedFramesX)
    }

    private static var supportsHEVCHardwareEncoding: Bool {
        var encoders: CFArray?
        guard VTCopyVideoEncoderList(nil, &encoders) == noErr,
              let entries = encoders as? [[String: Any]] else {
            return false
        }
        return entries.contains {
            ($0[kVTVideoEncoderList_CodecType as String] as? NSNumber)?.uint32Value == kCMVideoCodecType_HEVC &&
                $0[kVTVideoEncoderList_IsHardwareAccelerated as String] as? Bool == true
        }
    }

    private func videoRoundTrip(hdr: Bool, codedFramesX: Bool) async throws {
        let input = try makeInput(hdr: hdr)
        let inputFormat = try #require(input.formatDescription)
        #expect(!inputFormat.isCompressed)

        let encoder = VideoCodec()
        encoder.settings = .init(
            videoSize: .init(width: 192, height: 108),
            profileLevel: (hdr ? kVTProfileLevel_HEVC_Main10_AutoLevel : kVTProfileLevel_H264_Baseline_AutoLevel) as String,
            allowFrameReordering: false
        )
        let encodedOutput = encoder.outputStream
        encoder.startRunning()
        encoder.append(input)
        let compressionSession = try #require(encoder.session) as! VTCompressionSession
        #expect(VTCompressionSessionCompleteFrames(compressionSession, untilPresentationTimeStamp: .invalid) == noErr)
        encoder.stopRunning()
        var encodedFrames: [CMSampleBuffer] = []
        for await frame in encodedOutput {
            encodedFrames.append(frame)
        }
        let encoded = try #require(encodedFrames.first)
        let encodedFormat = try #require(encoded.formatDescription)
        #expect(encodedFormat.isCompressed)
        #expect(encodedFormat.isHDR == hdr)

        let sequence = try #require(RTMPVideoMessage(streamId: 1, timestamp: 0, formatDescription: encodedFormat))
        let receivedFormat = try #require(sequence.makeFormatDescription())
        #expect(receivedFormat.isHDR == hdr)
        if hdr {
            let atoms = try #require(CMFormatDescriptionGetExtension(encodedFormat, extensionKey: kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms) as? NSDictionary)
            let configuration = HEVCDecoderConfigurationRecord(data: try #require(atoms["hvcC"] as? Data))
            #expect(configuration.generalProfileIdc == 2)
            #expect(configuration.bitDepthLumaMinus8 == 2)
            #expect(configuration.bitDepthChromaMinus8 == 2)
            try expectHLG(receivedFormat)
        }

        var message = try #require(RTMPVideoMessage(streamId: 1, timestamp: 0, sampleBuffer: encoded))
        if hdr && codedFramesX {
            // CodedFramesX omits the composition-time field.
            message.payload[0] = (message.payload[0] & 0xF0) | RTMPVideoPacketType.codedFramesX.rawValue
            message.payload.removeSubrange(5..<8)
            #expect(message.compositionTime == 0)
        }
        let received = try #require(message.makeSampleBuffer(.init(value: 1, timescale: 30), formatDesciption: receivedFormat))
        if hdr && codedFramesX {
            #expect(received.presentationTimeStamp == CMTime(value: 1, timescale: 30))
        }
        let decoder = VideoCodec()
        let decodedOutput = decoder.outputStream
        decoder.startRunning()
        decoder.append(received)
        let decompressionSession = try #require(decoder.session) as! VTDecompressionSession
        #expect(VTDecompressionSessionWaitForAsynchronousFrames(decompressionSession) == noErr)
        decoder.stopRunning()
        var decodedFrames: [CMSampleBuffer] = []
        for await frame in decodedOutput {
            decodedFrames.append(frame)
        }
        let decoded = try #require(decodedFrames.first)
        let decodedFormat = try #require(decoded.formatDescription)
        #expect(!decodedFormat.isCompressed)
        #expect(decodedFormat.isHDR == hdr)
        if hdr {
            let image = try #require(decoded.imageBuffer)
            #expect(CVPixelBufferGetPixelFormatType(image) == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange)
            try expectHLG(decodedFormat)
            #expect(CVPixelBufferLockBaseAddress(image, .readOnly) == kCVReturnSuccess)
            defer {
                CVPixelBufferUnlockBaseAddress(image, .readOnly)
            }
            let luma = try #require(CVPixelBufferGetBaseAddressOfPlane(image, 0)).assumingMemoryBound(to: UInt16.self).pointee >> 6
            #expect(abs(Int(luma) - 900) < 16)
        }
    }

    @Test(arguments: [kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange, kCVPixelFormatType_420YpCbCr10BiPlanarFullRange])
    func tenBitInputIsUncompressed(pixelFormat: OSType) throws {
        var format: CMVideoFormatDescription?
        #expect(CMVideoFormatDescriptionCreate(allocator: kCFAllocatorDefault, codecType: pixelFormat, width: 192, height: 108, extensions: nil, formatDescriptionOut: &format) == noErr)
        #expect(try #require(format).isCompressed == false)
    }

    private func expectHLG(_ format: CMFormatDescription) throws {
        #expect(CMFormatDescriptionGetExtension(format, extensionKey: kCMFormatDescriptionExtension_ColorPrimaries) as? String == kCMFormatDescriptionColorPrimaries_ITU_R_2020 as String)
        #expect(CMFormatDescriptionGetExtension(format, extensionKey: kCMFormatDescriptionExtension_TransferFunction) as? String == kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String)
        #expect(CMFormatDescriptionGetExtension(format, extensionKey: kCMFormatDescriptionExtension_YCbCrMatrix) as? String == kCMFormatDescriptionYCbCrMatrix_ITU_R_2020 as String)
    }

    private func makeInput(hdr: Bool) throws -> CMSampleBuffer {
        var image: CVPixelBuffer?
        let mode: DynamicRangeMode = hdr ? .hdr : .sdr
        #expect(CVPixelBufferCreate(kCFAllocatorDefault, 192, 108, mode.videoFormat, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &image) == kCVReturnSuccess)
        let pixelBuffer = try #require(image)
        mode.attach(pixelBuffer)
        #expect(CVPixelBufferLockBaseAddress(pixelBuffer, []) == kCVReturnSuccess)
        for plane in 0..<CVPixelBufferGetPlaneCount(pixelBuffer) {
            let address = try #require(CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, plane))
            let count = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, plane) * CVPixelBufferGetHeightOfPlane(pixelBuffer, plane)
            if hdr {
                address.assumingMemoryBound(to: UInt16.self).initialize(repeating: (plane == 0 ? 900 : 512) << 6, count: count / 2)
            } else {
                address.assumingMemoryBound(to: UInt8.self).initialize(repeating: 128, count: count)
            }
        }
        #expect(CVPixelBufferUnlockBaseAddress(pixelBuffer, []) == kCVReturnSuccess)
        var format: CMVideoFormatDescription?
        #expect(CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescriptionOut: &format) == noErr)
        var sample: CMSampleBuffer?
        var timing = CMSampleTimingInfo(duration: .init(value: 1, timescale: 30), presentationTimeStamp: .init(value: 1, timescale: 30), decodeTimeStamp: .invalid)
        #expect(CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescription: try #require(format), sampleTiming: &timing, sampleBufferOut: &sample) == noErr)
        return try #require(sample)
    }
}
