import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox
import VPXBridge

/// A synchronous encoder. Confine the instance and its calls to one actor or serial executor.
@available(iOS 16.0, tvOS 16.0, macCatalyst 16.0, *)
public final class VPXVideoEncoder {
    private var context: OpaquePointer?
    private var transfer: VTPixelTransferSession?
    private var pixelBuffer: CVPixelBuffer?
    private var formatDescription: CMFormatDescription
    private var settings: VPXVideoCodecSettings
    private var finished = false
    private var lastPTS: Int64?
    private var chroma: [UInt8]
    private let width: Int
    private let height: Int

    /// Creates an encoder and allocates its conversion buffers.
    /// - Parameter settings: Output dimensions, codec, rate control, and scaling configuration.
    /// - Throws: ``VPXVideoCodecError`` if settings are invalid or codec allocation fails.
    public init(settings: VPXVideoCodecSettings = .init()) throws {
        let codec = settings.format.identifier
        let size = settings.videoSize
        let maximum = codec == 8 ? 16383.0 : 65535.0
        guard size.width.isFinite, size.height.isFinite,
              size.width >= 2, size.height >= 2, size.width <= maximum, size.height <= maximum,
              size.width.rounded() == size.width, size.height.rounded() == size.height,
              Int(size.width).isMultiple(of: 2), Int(size.height).isMultiple(of: 2),
              settings.maxKeyFrameIntervalDuration.isFinite, settings.maxKeyFrameIntervalDuration >= 0.000001,
              settings.maxKeyFrameIntervalDuration <= 3600, size.width * size.height <= 16_777_216 else {
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
                                        Int64((settings.maxKeyFrameIntervalDuration * 1_000_000).rounded()), Self.isConstantBitRate(settings) ? 1 : 0, &status)
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

    /// Updates bitrate and expected frame-rate hints without recreating the codec.
    /// - Parameter settings: The complete configuration. Only `bitRate` and `expectedFrameRate` may change.
    /// - Throws: ``VPXVideoCodecError/invalidSettings`` for other changes, or
    ///   ``VPXVideoCodecError/invalidSession`` after finishing or invalidation.
    public func update(_ settings: VPXVideoCodecSettings) throws {
        guard let context, !finished else { throw VPXVideoCodecError.invalidSession }
        guard settings.videoSize == self.settings.videoSize, settings.format == self.settings.format,
              settings.scalingMode == self.settings.scalingMode, settings.bitRateMode == self.settings.bitRateMode,
              settings.maxKeyFrameIntervalDuration == self.settings.maxKeyFrameIntervalDuration else {
            throw VPXVideoCodecError.invalidSettings
        }
        let fps = try Self.frameRate(settings)
        try checkCodec(hk_vpx_encoder_update(context, try Self.bitrate(settings), fps))
        self.settings = settings
    }

    /// Compresses an 8-bit image sample synchronously.
    ///
    /// Accepts NV12, planar YUV 4:2:0, BGRA, or ARGB. Input is scaled and converted to
    /// video-range YUV 4:2:0. Presentation timestamps must be numeric, epoch zero,
    /// and strictly increasing at microsecond precision. An invalid duration uses
    /// the expected frame rate. Calls must be serialized with all other operations.
    /// - Parameter sampleBuffer: An uncompressed image sample with a presentation timestamp.
    /// - Returns: Owned raw VP8/VP9 packets, with timing and keyframe attachments.
    ///   Packet storage remains valid after later calls or invalidation.
    /// - Throws: ``VPXVideoCodecError`` for an unsupported image, invalid timestamp,
    ///   inactive session, or a conversion/codec failure.
    public func encode(_ sampleBuffer: CMSampleBuffer) throws -> [CMSampleBuffer] {
        guard let context, !finished, let transfer, let pixelBuffer else { throw VPXVideoCodecError.invalidSession }
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
        guard pts.isNumeric, pts.epoch == 0, lastPTS.map({ pts.value > $0 }) ?? true else { throw VPXVideoCodecError.invalidTimestamp }
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
        lastPTS = pts.value
        return try packets()
    }

    /// Drains pending packets and ends input for this encoder.
    /// - Returns: Remaining owned packets. Repeated calls return an empty array.
    /// - Throws: ``VPXVideoCodecError`` if invalidated or flushing fails.
    ///
    /// Create a new encoder to resume input. Call this before ``invalidate()`` to retain pending output.
    public func finish() throws -> [CMSampleBuffer] {
        guard let context else { throw VPXVideoCodecError.invalidSession }
        if finished { return [] }
        try checkCodec(hk_vpx_encoder_flush(context))
        finished = true
        return try packets()
    }

    private func packets() throws -> [CMSampleBuffer] {
        var outputPackets: [CMSampleBuffer] = []
        var size = 0
        var outputPTS: Int64 = 0
        var outputDuration: UInt = 0
        var keyframe: Int32 = 0
        while let bytes = hk_vpx_encoder_next_packet(context, &size, &outputPTS, &outputDuration, &keyframe) {
            guard let block = makeBlockBuffer(Data(bytes: bytes, count: size)) else {
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
            if keyframe == 0, let attachments = CMSampleBufferGetSampleAttachmentsArray(output, createIfNecessary: true) {
                let values = attachments as NSArray
                if let first = values.firstObject as? NSMutableDictionary { first[kCMSampleAttachmentKey_NotSync] = true }
            }
            outputPackets.append(output)
        }
        return outputPackets
    }

    /// Releases native resources. Repeated calls are safe; further encoding fails.
    public func invalidate() {
        hk_vpx_destroy(context)
        context = nil
        if let transfer { VTPixelTransferSessionInvalidate(transfer) }
        transfer = nil
        pixelBuffer = nil
    }

    private static func bitrate(_ settings: VPXVideoCodecSettings) throws -> UInt32 {
        guard settings.bitRate > 0, settings.bitRate / 1000 <= Int(UInt32.max) else {
            throw VPXVideoCodecError.invalidSettings
        }
        return UInt32(max(1, settings.bitRate / 1000))
    }

    private static func frameRate(_ settings: VPXVideoCodecSettings) throws -> Double {
        let fps = settings.expectedFrameRate
        guard fps.isFinite, fps >= 0.001, fps <= 1_000_000 else { throw VPXVideoCodecError.invalidSettings }
        return fps
    }

    private static func isConstantBitRate(_ settings: VPXVideoCodecSettings) -> Bool {
        settings.bitRateMode == .constant
    }
}

