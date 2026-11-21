import CoreMedia
import CoreVideo
import Foundation
import Testing
import AOMHaishinKit

@Suite struct AOMVideoCodecTests {
    @Test
    func roundTripAndOwnedOutputs() throws {
        for _ in 0..<2 {
            var settings = AOMVideoCodecSettings(videoSize: CGSize(width: 64, height: 48), bitRate: 300_000)
            let encoder = try AOMVideoEncoder(settings: settings)
            var packets: [CMSampleBuffer] = []
            var firstBytes = Data()
            for index in 0..<4 {
                if index == 2 { settings.bitRate = 500_000; try encoder.update(settings) }
                packets += try encoder.encode(frame(index: index))
                if index == 0 { firstBytes = try bytes(try #require(packets.first)) }
            }
            packets += try encoder.finish()
            #expect(try encoder.finish().isEmpty)
            #expect(packets.count == 4)
            let first = try #require(packets.first)
            #expect(try bytes(first) == firstBytes)
            #expect(CMFormatDescriptionGetMediaSubType(try #require(first.formatDescription)) == kCMVideoCodecType_AV1)
            #expect(first.sampleAttachments[0][.notSync] == nil)
            #expect(packets.dropFirst().contains { $0.sampleAttachments[0][.notSync] != nil })
            #expect(throws: AOMVideoCodecError.self) { try encoder.encode(frame(index: 4)) }
            let decoder = try AOMVideoDecoder()
            let frames = try packets.flatMap { try decoder.decode($0) }
            #expect(frames.count == packets.count)
            for (index, sample) in frames.enumerated() {
                let pixel = try #require(sample.imageBuffer)
                #expect(CVPixelBufferGetWidth(pixel) == 64 && CVPixelBufferGetHeight(pixel) == 48)
                #expect(abs(sample.presentationTimeStamp.seconds - (10 + Double(index) / 30)) < 0.000002)
                #expect(abs(sample.duration.seconds - 1 / 30.0) < 0.000002)
                #expect(CVPixelBufferLockBaseAddress(pixel, .readOnly) == kCVReturnSuccess)
                let y = try #require(CVPixelBufferGetBaseAddressOfPlane(pixel, 0)?.assumingMemoryBound(to: UInt8.self))
                #expect(abs(Int(y.pointee) - (80 + index)) < 12)
                let uv = try #require(CVPixelBufferGetBaseAddressOfPlane(pixel, 1)?.assumingMemoryBound(to: UInt8.self))
                #expect(abs(Int(uv[0]) - 96) < 12)
                #expect(abs(Int(uv[1]) - 160) < 12)
                CVPixelBufferUnlockBaseAddress(pixel, .readOnly)
            }
            encoder.invalidate(); encoder.invalidate(); decoder.invalidate(); decoder.invalidate()
            #expect(throws: AOMVideoCodecError.self) { try decoder.decode(first) }
        }
    }

    @Test
    func preparedInputKeyframesAndRejectedChanges() throws {
        let settings = AOMVideoCodecSettings(videoSize: CGSize(width: 64, height: 48), maxKeyFrameIntervalDuration: 2, bitRateMode: .constant)
        let encoder = try AOMVideoEncoder(settings: settings)
        var invalid = settings; invalid.videoSize.width = 128
        #expect(throws: AOMVideoCodecError.self) { try encoder.update(invalid) }
        var packets: [CMSampleBuffer] = []
        for input in [try frame(index: 0, width: 96, height: 72),
                      try frame(index: 0, bgra: true),
                      try frame(index: 0, pixelFormat: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
                      try frame(index: 0, pixelFormat: kCVPixelFormatType_420YpCbCr8PlanarFullRange)] {
            #expect(throws: AOMVideoCodecError.self) { try encoder.encode(input) }
        }
        for index in [0, 1, 75] { packets += try encoder.encode(frame(index: index)) }
        packets += try encoder.finish()
        #expect(packets.count == 3)
        #expect(try #require(packets.last).sampleAttachments[0][.notSync] == nil)
        let decoder = try AOMVideoDecoder()
        let frames = try packets.flatMap { try decoder.decode($0) }
        #expect(frames.count == 3)
        #expect(CVPixelBufferGetWidth(try #require(frames.first?.imageBuffer)) == 64)
        #expect(CVPixelBufferGetHeight(try #require(frames.first?.imageBuffer)) == 48)

    }

    @Test
    func invalidSettingsAndTimestampsFailDirectly() throws {
        var invalid: [AOMVideoCodecSettings] = []
        var value = AOMVideoCodecSettings(); value.videoSize.width = 63; invalid.append(value)
        value = .init(); value.bitRate = 0; invalid.append(value)
        value = .init(); value.expectedFrameRate = .nan; invalid.append(value)
        value = .init(); value.expectedFrameRate = 1e-100; invalid.append(value)
        value = .init(); value.maxKeyFrameIntervalDuration = .infinity; invalid.append(value)
        for settings in invalid { #expect(throws: AOMVideoCodecError.self) { try AOMVideoEncoder(settings: settings) } }
        let encoder = try AOMVideoEncoder(settings: .init(videoSize: CGSize(width: 64, height: 48)))
        let first = try frame(index: 0)
        let packets = try encoder.encode(first)
        #expect(throws: AOMVideoCodecError.self) { try encoder.encode(first) }
        #expect(try encoder.encode(frame(index: 1)).count == 1)
        let decoder = try AOMVideoDecoder()
        #expect(throws: AOMVideoCodecError.self) { try decoder.decode(first) }
        let corrupt = try #require(packets.first)
        let block = try #require(corrupt.dataBuffer)
        let zeros = [UInt8](repeating: 0, count: CMBlockBufferGetDataLength(block))
        #expect(zeros.withUnsafeBytes { CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: $0.count) } == noErr)
        #expect(throws: AOMVideoCodecError.self) { try decoder.decode(corrupt) }
    }

    @Test
    func statisticsTrackSuccessfulFramesAndOwnedOutput() throws {
        let encoder = try AOMVideoEncoder(settings: .init(videoSize: CGSize(width: 64, height: 48)))
        let initial = encoder.statistics
        #expect(initial.submittedFrameCount == 0 && initial.averageEncodingDuration == 0)
        #expect(throws: AOMVideoCodecError.self) { try encoder.encode(frame(index: 0, bgra: true)) }
        #expect(encoder.statistics == initial)
        var packets = try encoder.encode(frame(index: 0))
        let snapshot = encoder.statistics
        packets += try encoder.encode(frame(index: 1))
        packets += try encoder.finish()
        let result = encoder.statistics
        #expect(snapshot.submittedFrameCount == 1)
        #expect(result.submittedFrameCount == 2)
        #expect(result.outputPacketCount == UInt64(packets.count))
        #expect(result.encodedByteCount == packets.reduce(UInt64(0)) { $0 + UInt64($1.totalSampleSize) })
        #expect(result.lastEncodingDuration >= 0 && result.totalEncodingDuration >= result.lastEncodingDuration)
        #expect(result.maximumEncodingDuration >= result.lastEncodingDuration)
        #expect(result.averageEncodingDuration == result.totalEncodingDuration / 2)
        #expect(try JSONDecoder().decode(AOMVideoEncoderStatistics.self, from: JSONEncoder().encode(result)) == result)
        encoder.invalidate()
        #expect(encoder.statistics == result)
    }

    private func bytes(_ sample: CMSampleBuffer) throws -> Data {
        let block = try #require(sample.dataBuffer)
        var data = Data(count: CMBlockBufferGetDataLength(block))
        let status = data.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: $0.count, destination: $0.baseAddress!) }
        #expect(status == noErr)
        return data
    }

    private func frame(index: Int, width: Int = 64, height: Int = 48, bgra: Bool = false, pixelFormat: OSType = kCVPixelFormatType_420YpCbCr8Planar) throws -> CMSampleBuffer {
        var pixel: CVPixelBuffer?
        #expect(CVPixelBufferCreate(nil, width, height, bgra ? kCVPixelFormatType_32BGRA : pixelFormat,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pixel) == kCVReturnSuccess)
        let image = try #require(pixel)
        #expect(CVPixelBufferLockBaseAddress(image, []) == kCVReturnSuccess)
        if bgra {
            let base = try #require(CVPixelBufferGetBaseAddress(image)?.assumingMemoryBound(to: UInt8.self))
            for row in 0..<height { for col in 0..<width {
                let p = base.advanced(by: row * CVPixelBufferGetBytesPerRow(image) + col * 4)
                p[0] = UInt8(80 + index); p[1] = UInt8(80 + index); p[2] = UInt8(80 + index); p[3] = 255
            } }
        } else {
            for plane in 0..<CVPixelBufferGetPlaneCount(image) {
                memset(CVPixelBufferGetBaseAddressOfPlane(image, plane), plane == 0 ? Int32(80 + index) : (plane == 1 ? 96 : 160),
                    CVPixelBufferGetBytesPerRowOfPlane(image, plane) * CVPixelBufferGetHeightOfPlane(image, plane))
            }
        }
        CVPixelBufferUnlockBaseAddress(image, [])
        var format: CMFormatDescription?
        #expect(CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: image, formatDescriptionOut: &format) == noErr)
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30), presentationTimeStamp: CMTime(value: 300 + Int64(index), timescale: 30), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        #expect(CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: image, formatDescription: try #require(format), sampleTiming: &timing, sampleBufferOut: &sample) == noErr)
        return try #require(sample)
    }
}
