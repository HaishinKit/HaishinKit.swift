import CoreMedia
import CoreVideo
import Foundation
import HaishinKit
import VideoToolbox
import VPXBridge

@available(iOS 16.0, tvOS 16.0, macCatalyst 16.0, *)
final class VPXEncoder: VideoCodecSession {
    private var context: OpaquePointer?
    private var transfer: VTPixelTransferSession?
    private var pixelBuffer: CVPixelBuffer?
    private var formatDescription: CMFormatDescription
    private var settings: VideoCodecSettings
    private var chroma: [UInt8]
    private let width: Int
    private let height: Int

    init(codec: Int32, settings: VideoCodecSettings) throws {
        let size = settings.videoSize
        let maximum = codec == 8 ? 16383.0 : 65535.0
        guard size.width.isFinite, size.height.isFinite,
              size.width >= 2, size.height >= 2, size.width <= maximum, size.height <= maximum,
              size.width.rounded() == size.width, size.height.rounded() == size.height,
              Int(size.width).isMultiple(of: 2), Int(size.height).isMultiple(of: 2),
              settings.maxKeyFrameIntervalDuration > 0,
              Self.isSupportedBitRateMode(settings) else {
            throw VPXVideoCodecError.invalidSettings
        }
        width = Int(size.width)
        height = Int(size.height)
        self.settings = settings
        chroma = []
        let fps = try Self.frameRate(settings)
        var description: CMFormatDescription?
        try checkStatus(CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: settings.format.codecType,
            width: Int32(width), height: Int32(height),
            extensions: nil, formatDescriptionOut: &description
        ))
        guard let description else { throw VPXVideoCodecError.unsupportedFormat }
        formatDescription = description
        var status: Int32 = 0
        context = hk_vpx_encoder_create(codec, UInt32(width), UInt32(height), try Self.bitrate(settings), fps,
                                        Int64(settings.maxKeyFrameIntervalDuration) * 1_000_000, Self.isConstantBitRate(settings) ? 1 : 0, &status)
        guard context != nil else { throw VPXVideoCodecError.codec(status) }
        chroma = [UInt8](repeating: 0, count: width * height / 2)
        do {
            try checkStatus(VTPixelTransferSessionCreate(allocator: kCFAllocatorDefault, pixelTransferSessionOut: &transfer))
            guard let transfer else { throw VPXVideoCodecError.unsupportedFormat }
            try checkStatus(VTSessionSetProperty(transfer, key: kVTPixelTransferPropertyKey_ScalingMode, value: settings.scalingMode.rawValue as CFString))
            try checkStatus(CVPixelBufferCreate(
                kCFAllocatorDefault, width, height, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pixelBuffer
            ))
        } catch {
            invalidate()
            throw error
        }
    }

    deinit {
        invalidate()
    }

    func update(_ settings: VideoCodecSettings) throws {
        guard let context else { throw VPXVideoCodecError.invalidSession }
        guard Self.isSupportedBitRateMode(settings) else { throw VPXVideoCodecError.invalidSettings }
        let fps = try Self.frameRate(settings)
        try checkCodec(hk_vpx_encoder_update(context, try Self.bitrate(settings), fps))
        self.settings = settings
    }

    func convert(_ sampleBuffer: CMSampleBuffer, continuation: AsyncStream<CMSampleBuffer>.Continuation?) throws {
        guard let context, let transfer, let pixelBuffer else { throw VPXVideoCodecError.invalidSession }
        guard let source = sampleBuffer.imageBuffer else { throw VPXVideoCodecError.unsupportedFormat }
        switch CVPixelBufferGetPixelFormatType(source) {
        case kCVPixelFormatType_32BGRA, kCVPixelFormatType_32ARGB,
             kCVPixelFormatType_420YpCbCr8Planar, kCVPixelFormatType_420YpCbCr8PlanarFullRange,
             kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
            break
        default:
            throw VPXVideoCodecError.unsupportedFormat
        }
        let pts = CMTimeConvertScale(sampleBuffer.presentationTimeStamp, timescale: 1_000_000, method: .default)
        guard pts.isNumeric else { throw VPXVideoCodecError.invalidTimestamp }
        let duration = CMTimeConvertScale(sampleBuffer.duration, timescale: 1_000_000, method: .default)
        let ticks = duration.isNumeric && duration.value > 0 ? duration.value : max(1, Int64((1_000_000 / (try Self.frameRate(settings))).rounded()))
        try checkStatus(VTPixelTransferSessionTransferImage(transfer, from: source, to: pixelBuffer))
        try checkStatus(CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly))
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let y = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0)?.assumingMemoryBound(to: UInt8.self),
              let uv = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1)?.assumingMemoryBound(to: UInt8.self) else {
            throw VPXVideoCodecError.unsupportedFormat
        }
        let yStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let uvStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
        let chromaSize = width * height / 4
        try chroma.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else { throw VPXVideoCodecError.unsupportedFormat }
            let u = base
            let v = base.advanced(by: chromaSize)
            for row in 0..<height / 2 {
                for col in 0..<width / 2 {
                    u[row * width / 2 + col] = uv[row * uvStride + col * 2]
                    v[row * width / 2 + col] = uv[row * uvStride + col * 2 + 1]
                }
            }
            try checkCodec(hk_vpx_encoder_encode(context, y, Int32(yStride), u, Int32(width / 2), v, Int32(width / 2), pts.value, UInt(ticks)))
        }
        var size = 0
        var outputPTS: Int64 = 0
        var outputDuration: UInt = 0
        var keyframe: Int32 = 0
        while let bytes = hk_vpx_encoder_next_packet(context, &size, &outputPTS, &outputDuration, &keyframe) {
            guard let block = Data(bytes: bytes, count: size).makeBlockBuffer() else {
                throw VPXVideoCodecError.coreMedia(kCMBlockBufferStructureAllocationFailedErr)
            }
            var timing = CMSampleTimingInfo(
                duration: CMTime(value: Int64(outputDuration), timescale: 1_000_000),
                presentationTimeStamp: CMTime(value: outputPTS, timescale: 1_000_000), decodeTimeStamp: .invalid
            )
            var output: CMSampleBuffer?
            try checkStatus(CMSampleBufferCreateReady(
                allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: formatDescription,
                sampleCount: 1, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &output
            ))
            guard let output else { throw VPXVideoCodecError.unsupportedFormat }
            output.isNotSync = keyframe == 0
            continuation?.yield(output)
        }
    }

    func invalidate() {
        hk_vpx_destroy(context)
        context = nil
        if let transfer { VTPixelTransferSessionInvalidate(transfer) }
        transfer = nil
        pixelBuffer = nil
    }

    private static func bitrate(_ settings: VideoCodecSettings) throws -> UInt32 {
        guard settings.bitRate > 0, settings.bitRate / 1000 <= Int(UInt32.max) else {
            throw VPXVideoCodecError.invalidSettings
        }
        return UInt32(max(1, settings.bitRate / 1000))
    }

    private static func frameRate(_ settings: VideoCodecSettings) throws -> Double {
        let fps = settings.expectedFrameRate ?? 30
        guard fps.isFinite, fps > 0, fps <= 1_000_000 else { throw VPXVideoCodecError.invalidSettings }
        return fps
    }

    private static func isConstantBitRate(_ settings: VideoCodecSettings) -> Bool {
        if #available(iOS 16, tvOS 16, macOS 13, *), settings.bitRateMode == .constant { return true }
        return false
    }

    private static func isSupportedBitRateMode(_ settings: VideoCodecSettings) -> Bool {
        settings.bitRateMode == .average || isConstantBitRate(settings)
    }
}

final class VPXDecoder: VideoCodecSession {
    private var context: OpaquePointer?
    private var pool: CVPixelBufferPool?
    private var dimensions: (width: Int, height: Int, fullRange: Bool)?

    init(codec: Int32) throws {
        var status: Int32 = 0
        context = hk_vpx_decoder_create(codec, &status)
        guard context != nil else { throw VPXVideoCodecError.codec(status) }
    }

    deinit {
        invalidate()
    }

    func update(_ settings: VideoCodecSettings) throws {
    }

    func convert(_ sampleBuffer: CMSampleBuffer, continuation: AsyncStream<CMSampleBuffer>.Continuation?) throws {
        guard let context else { throw VPXVideoCodecError.invalidSession }
        guard let data = sampleBuffer.dataBuffer else { throw VPXVideoCodecError.unsupportedFormat }
        let count = CMBlockBufferGetDataLength(data)
        guard count > 0, count <= Int(UInt32.max) else { throw VPXVideoCodecError.unsupportedFormat }
        var bytes = [UInt8](repeating: 0, count: count)
        try bytes.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { throw VPXVideoCodecError.unsupportedFormat }
            try checkStatus(CMBlockBufferCopyDataBytes(data, atOffset: 0, dataLength: count, destination: base))
        }
        try bytes.withUnsafeBufferPointer { buffer in
            try checkCodec(hk_vpx_decoder_decode(context, buffer.baseAddress, UInt32(count)))
        }
        var image = HKVPXImage()
        while true {
            let result = hk_vpx_decoder_next_image(context, &image)
            guard result != 0 else { return }
            guard result > 0 else { throw VPXVideoCodecError.unsupportedFormat }
            let pixelBuffer = try makePixelBuffer(image)
            var format: CMFormatDescription?
            try checkStatus(CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescriptionOut: &format))
            guard let format else { throw VPXVideoCodecError.unsupportedFormat }
            var timing = CMSampleTimingInfo(duration: sampleBuffer.duration, presentationTimeStamp: sampleBuffer.presentationTimeStamp, decodeTimeStamp: .invalid)
            var output: CMSampleBuffer?
            try checkStatus(CMSampleBufferCreateReadyWithImageBuffer(
                allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer,
                formatDescription: format, sampleTiming: &timing, sampleBufferOut: &output
            ))
            if let output { continuation?.yield(output) }
        }
    }

    func invalidate() {
        hk_vpx_destroy(context)
        context = nil
        pool = nil
        dimensions = nil
    }

    private func makePixelBuffer(_ image: HKVPXImage) throws -> CVPixelBuffer {
        let width = Int(image.width)
        let height = Int(image.height)
        let fullRange = image.full_range != 0
        guard width > 0, height > 0, let sourceY = image.y, let sourceU = image.u, let sourceV = image.v else {
            throw VPXVideoCodecError.unsupportedFormat
        }
        if dimensions?.width != width || dimensions?.height != height || dimensions?.fullRange != fullRange {
            let attributes: [CFString: Any] = [
                kCVPixelBufferWidthKey: width, kCVPixelBufferHeightKey: height,
                kCVPixelBufferPixelFormatTypeKey: fullRange ? kCVPixelFormatType_420YpCbCr8BiPlanarFullRange : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                kCVPixelBufferIOSurfacePropertiesKey: [:], kCVPixelBufferMetalCompatibilityKey: true
            ]
            try checkStatus(CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes as CFDictionary, &pool))
            dimensions = (width, height, fullRange)
        }
        guard let pool else { throw VPXVideoCodecError.unsupportedFormat }
        var output: CVPixelBuffer?
        try checkStatus(CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &output))
        guard let output else { throw VPXVideoCodecError.unsupportedFormat }
        try checkStatus(CVPixelBufferLockBaseAddress(output, []))
        defer { CVPixelBufferUnlockBaseAddress(output, []) }
        guard let y = CVPixelBufferGetBaseAddressOfPlane(output, 0)?.assumingMemoryBound(to: UInt8.self),
              let uv = CVPixelBufferGetBaseAddressOfPlane(output, 1)?.assumingMemoryBound(to: UInt8.self) else {
            throw VPXVideoCodecError.unsupportedFormat
        }
        for row in 0..<height {
            memcpy(y.advanced(by: row * CVPixelBufferGetBytesPerRowOfPlane(output, 0)), sourceY.advanced(by: row * Int(image.y_stride)), width)
        }
        for row in 0..<(height + 1) / 2 {
            let destination = uv.advanced(by: row * CVPixelBufferGetBytesPerRowOfPlane(output, 1))
            for col in 0..<(width + 1) / 2 {
                destination[col * 2] = sourceU[row * Int(image.u_stride) + col]
                destination[col * 2 + 1] = sourceV[row * Int(image.v_stride) + col]
            }
        }
        return output
    }
}

private func checkStatus(_ status: OSStatus) throws {
    guard status == noErr else { throw VPXVideoCodecError.coreMedia(status) }
}

private func checkCodec(_ status: Int32) throws {
    guard status == 0 else { throw VPXVideoCodecError.codec(status) }
}
