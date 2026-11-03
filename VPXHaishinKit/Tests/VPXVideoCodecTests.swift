import CoreMedia
import CoreVideo
import Foundation
@testable import HaishinKit
import Testing
import VideoToolbox
import VPXHaishinKit

@testable import RTCHaishinKit
@testable import RTMPHaishinKit
@testable import SRTHaishinKit

@Suite struct VPXVideoCodecTests {
    @Test func registrationIsExplicitAndIdempotent() async throws {
        let registry = VideoCodecFactory()
        let before = await registry.supportedFormats(for: .compression)
        #expect(!before.contains(.vp8))
        #expect(!before.contains(.vp9))
        #expect(await VideoCodecFactory.shared.supportedFormats(for: .compression) == [.h264, .hevc])
        await registry.register(VPXVideoCodecFactory())
        await registry.register(VPXVideoCodecFactory())
        let available = [.h264, .hevc] + VPXVideoCodecFactory().supportedFormats(for: .compression)
        #expect(await registry.supportedFormats(for: .compression) == available)
        #expect(await registry.supportedFormats(for: .decompression) == [.h264, .hevc, .vp8, .vp9])
        // Independent registries and merely importing this module enable nothing.
        #expect(await VideoCodecFactory().supportedFormats(for: .compression) == [.h264, .hevc])
    }

    @Test(.enabled(if: !VPXVideoCodecFactory().supportedFormats(for: .compression).isEmpty), arguments: [VideoCodecSettings.Format.vp8, .vp9])
    func roundTrip(format: VideoCodecSettings.Format) async throws {
        let registry = VideoCodecFactory()
        await registry.register(VPXVideoCodecFactory())
        var settings = VideoCodecSettings(videoSize: CGSize(width: 64, height: 48), bitRate: 300_000, expectedFrameRate: 30, format: format)
        let input = try makeFrame(index: 0)
        let inputFormat = try #require(input.formatDescription)
        let encoder = try registry.makeSession(mode: .compression, settings: settings, inputFormat: inputFormat)
        let encoded = AsyncStream<CMSampleBuffer>.makeStream()
        for index in 0..<4 {
            if index == 2 {
                settings.bitRate = 500_000
                try encoder.update(settings)
            }
            try encoder.convert(makeFrame(index: index), continuation: encoded.continuation)
        }
        encoded.continuation.finish()
        var packets: [CMSampleBuffer] = []
        for await packet in encoded.stream { packets.append(packet) }
        #expect(packets.count == 4)
        let first = try #require(packets.first)
        #expect(CMFormatDescriptionGetMediaSubType(try #require(first.formatDescription)) == format.codecType)
        #expect(first.sampleAttachments[0][.notSync] == nil)
        #expect(packets.dropFirst().contains { !$0.sampleAttachments.isEmpty && $0.sampleAttachments[0][.notSync] != nil })
        // Decoding selects the codec from the bitstream format, not default H.264 settings.
        let decoder = try registry.makeSession(mode: .decompression, settings: .default, inputFormat: try #require(first.formatDescription))
        let decoded = AsyncStream<CMSampleBuffer>.makeStream()
        for packet in packets { try decoder.convert(packet, continuation: decoded.continuation) }
        decoded.continuation.finish()
        var frames: [CMSampleBuffer] = []
        for await frame in decoded.stream { frames.append(frame) }
        #expect(frames.count == packets.count)
        for (index, frame) in frames.enumerated() {
            let image = try #require(frame.imageBuffer)
            #expect(CVPixelBufferGetWidth(image) == 64)
            #expect(CVPixelBufferGetHeight(image) == 48)
            #expect(abs(frame.presentationTimeStamp.seconds - (10 + Double(index) / 30)) < 0.000002)
            #expect(abs(frame.duration.seconds - 1 / 30.0) < 0.000002)
            #expect(CVPixelBufferLockBaseAddress(image, .readOnly) == kCVReturnSuccess)
            let y = try #require(CVPixelBufferGetBaseAddressOfPlane(image, 0)?.assumingMemoryBound(to: UInt8.self))
            #expect(abs(Int(y.pointee) - (80 + index)) < 12)
            CVPixelBufferUnlockBaseAddress(image, .readOnly)
        }
        encoder.invalidate()
        encoder.invalidate()
        decoder.invalidate()
        decoder.invalidate()
        #expect(throws: VPXVideoCodecError.self) {
            try encoder.convert(input, continuation: nil)
        }
    }

    @Test(.enabled(if: supportsH264Encoding()), .timeLimit(.minutes(1)))
    func standardH264StillConvertsWithoutRegistration() async throws {
        let registry = VideoCodecFactory()
        let input = try makeFrame(index: 0)
        let encoder = try registry.makeSession(mode: .compression,
            settings: .init(videoSize: CGSize(width: 64, height: 48), allowFrameReordering: false, isHardwareAcceleratedEnabled: false),
            inputFormat: try #require(input.formatDescription))
        let packets = AsyncStream<CMSampleBuffer>.makeStream()
        try encoder.convert(input, continuation: packets.continuation)
        let packet = try #require(await firstOutput(packets.stream))
        #expect(CMFormatDescriptionGetMediaSubType(try #require(packet.formatDescription)) == kCMVideoCodecType_H264)
        encoder.invalidate()
        encoder.invalidate()
        let decoder = try registry.makeSession(mode: .decompression, settings: .default, inputFormat: try #require(packet.formatDescription))
        let frames = AsyncStream<CMSampleBuffer>.makeStream()
        try decoder.convert(packet, continuation: frames.continuation)
        let frame = try #require(await firstOutput(frames.stream))
        #expect(CVPixelBufferGetWidth(try #require(frame.imageBuffer)) == 64)
        decoder.invalidate()
    }

    private func firstOutput(_ stream: AsyncStream<CMSampleBuffer>) async -> CMSampleBuffer? {
        await withTaskGroup(of: CMSampleBuffer?.self) { group in
            group.addTask {
                var iterator = stream.makeAsyncIterator()
                return await iterator.next()
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    @Test func invalidSettingsAndCompressedDataFail() async throws {
        let factory = VPXVideoCodecFactory()
        let input = try makeFrame(index: 0)
        let description = try #require(input.formatDescription)
        for settings in [VideoCodecSettings(videoSize: CGSize(width: 63, height: 48), format: .vp8),
                         VideoCodecSettings(bitRate: 0, format: .vp9),
                         VideoCodecSettings(expectedFrameRate: .nan, format: .vp8)] {
            #expect(throws: VPXVideoCodecError.self) {
                try factory.makeSession(mode: .compression, settings: settings, inputFormat: description)
            }
        }
        var compressedFormat: CMFormatDescription?
        #expect(CMVideoFormatDescriptionCreate(allocator: kCFAllocatorDefault, codecType: VideoCodecSettings.Format.vp9.codecType, width: 64, height: 48, extensions: nil, formatDescriptionOut: &compressedFormat) == noErr)
        let decoder = try factory.makeSession(mode: .decompression, settings: .default, inputFormat: try #require(compressedFormat))
        #expect(throws: VPXVideoCodecError.self) {
            try decoder.convert(input, continuation: nil)
        }
        decoder.invalidate()
    }

    @Test(arguments: [VideoCodecSettings.Format.vp8, .vp9])
    func registrationDoesNotEnableTransports(format: VideoCodecSettings.Format) async {
        let settings = VideoCodecSettings(format: format)
        do { try await RTCStream().setVideoSettings(settings); Issue.record("RTC accepted an unimplemented transport codec") } catch { }
        do { try await RTMPStream(connection: RTMPConnection()).setVideoSettings(settings); Issue.record("RTMP accepted an unimplemented transport codec") } catch { }
        do { try await SRTStream(connection: SRTConnection()).setVideoSettings(settings); Issue.record("SRT accepted an unimplemented transport codec") } catch { }
    }

    @Test(.enabled(if: !VPXVideoCodecFactory().supportedFormats(for: .compression).isEmpty), arguments: [VideoCodecSettings.Format.vp8, .vp9])
    func existingPipelineUsesProviderAndCanRestart(format: VideoCodecSettings.Format) async throws {
        let registry = VideoCodecFactory()
        await registry.register(VPXVideoCodecFactory())
        let encoder = VideoCodec(factory: registry)
        encoder.settings = .init(videoSize: CGSize(width: 64, height: 48), format: format)
        let decoder = VideoCodec(factory: registry)
        for _ in 0..<2 {
            let packets = encoder.outputStream
            encoder.startRunning()
            for index in 0..<3 {
                encoder.append(try makeFrame(index: index, width: 96, height: 72, pixelFormat: kCVPixelFormatType_32BGRA))
            }
            encoder.stopRunning()
            let frames = decoder.outputStream
            decoder.startRunning()
            var packetCount = 0
            for await packet in packets {
                #expect(packet.formatDescription?.isCompressed == true)
                decoder.append(packet)
                packetCount += 1
            }
            decoder.stopRunning()
            #expect(packetCount == 3)
            var frameCount = 0
            for await frame in frames {
                let image = try #require(frame.imageBuffer)
                #expect(CVPixelBufferGetWidth(image) == 64)
                #expect(CVPixelBufferGetHeight(image) == 48)
                frameCount += 1
            }
            #expect(frameCount == 3)
        }
    }

    @Test(.enabled(if: !VPXVideoCodecFactory().supportedFormats(for: .compression).isEmpty), arguments: [VideoCodecSettings.Format.vp8, .vp9])
    func keyframeIntervalUsesTimeRatherThanFrameCount(format: VideoCodecSettings.Format) async throws {
        let input = try makeFrame(index: 0)
        let encoder = try VPXVideoCodecFactory().makeSession(mode: .compression,
            settings: .init(videoSize: CGSize(width: 64, height: 48), maxKeyFrameIntervalDuration: 2, format: format),
            inputFormat: try #require(input.formatDescription))
        let packets = AsyncStream<CMSampleBuffer>.makeStream()
        for index in [0, 1, 75] { try encoder.convert(makeFrame(index: index), continuation: packets.continuation) }
        packets.continuation.finish()
        var output: [CMSampleBuffer] = []
        for await packet in packets.stream { output.append(packet) }
        #expect(output.count == 3)
        let last = try #require(output.last)
        #expect(last.sampleAttachments[0][.notSync] == nil)
        encoder.invalidate()
    }

    private func makeFrame(index: Int, width: Int = 64, height: Int = 48, pixelFormat: OSType = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) throws -> CMSampleBuffer {
        var pixelBuffer: CVPixelBuffer?
        #expect(CVPixelBufferCreate(kCFAllocatorDefault, width, height, pixelFormat, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pixelBuffer) == kCVReturnSuccess)
        let image = try #require(pixelBuffer)
        #expect(CVPixelBufferLockBaseAddress(image, []) == kCVReturnSuccess)
        if pixelFormat == kCVPixelFormatType_32BGRA {
            let base = try #require(CVPixelBufferGetBaseAddress(image)?.assumingMemoryBound(to: UInt8.self))
            for row in 0..<height {
                for col in 0..<width {
                    let pixel = base.advanced(by: row * CVPixelBufferGetBytesPerRow(image) + col * 4)
                    pixel[0] = UInt8(80 + index); pixel[1] = UInt8(80 + index)
                    pixel[2] = UInt8(80 + index); pixel[3] = 255
                }
            }
        } else {
            for plane in 0..<2 {
                let base = try #require(CVPixelBufferGetBaseAddressOfPlane(image, plane))
                memset(base, plane == 0 ? Int32(80 + index) : 128, CVPixelBufferGetBytesPerRowOfPlane(image, plane) * CVPixelBufferGetHeightOfPlane(image, plane))
            }
        }
        CVPixelBufferUnlockBaseAddress(image, [])
        var format: CMFormatDescription?
        #expect(CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: image, formatDescriptionOut: &format) == noErr)
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30), presentationTimeStamp: CMTime(value: 300 + Int64(index), timescale: 30), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        #expect(CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: image, formatDescription: try #require(format), sampleTiming: &timing, sampleBufferOut: &sample) == noErr)
        return try #require(sample)
    }
}

private func supportsH264Encoding() -> Bool {
    var encoders: CFArray?
    guard VTCopyVideoEncoderList(nil, &encoders) == noErr,
          let values = encoders as? [[CFString: Any]] else { return false }
    return values.contains { ($0[kVTVideoEncoderList_CodecType] as? NSNumber)?.uint32Value == kCMVideoCodecType_H264 }
}
