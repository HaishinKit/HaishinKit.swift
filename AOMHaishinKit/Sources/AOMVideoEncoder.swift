import CoreMedia
import CoreVideo
import Foundation
import Dispatch
import AOMBridge

/// A synchronous encoder. Confine the instance and its calls to one actor or serial executor.
public final class AOMVideoEncoder {
    /// Current lifetime statistics. Read on the same actor or serial executor as encode calls.
    /// Copy this Sendable value to forward a snapshot to a UI, history store, or report.
    public private(set) var statistics = AOMVideoEncoderStatistics()

    private var context: OpaquePointer?
    private var formatDescription: CMFormatDescription
    private var configuration: Data?
    private var settings: AOMVideoCodecSettings
    private var finished = false
    private var lastPTS: Int64?
    private let width: Int
    private let height: Int

    /// Creates a software encoder for caller-prepared I420 frames.
    /// - Parameter settings: Input/output dimensions and rate-control configuration.
    /// - Throws: ``AOMVideoCodecError`` if settings are invalid or codec allocation fails.
    public init(settings: AOMVideoCodecSettings = .init()) throws {
        let size = settings.videoSize
        let maximum = 65535.0
        guard size.width.isFinite, size.height.isFinite,
              size.width >= 2, size.height >= 2, size.width <= maximum, size.height <= maximum,
              size.width.rounded() == size.width, size.height.rounded() == size.height,
              Int(size.width).isMultiple(of: 2), Int(size.height).isMultiple(of: 2),
              settings.maxKeyFrameIntervalDuration.isFinite, settings.maxKeyFrameIntervalDuration >= 0.000001,
              settings.maxKeyFrameIntervalDuration <= 3600, size.width * size.height <= 16_777_216 else {
            throw AOMVideoCodecError.invalidSettings
        }
        width = Int(size.width)
        height = Int(size.height)
        self.settings = settings
        let fps = try Self.frameRate(settings)
        var description: CMFormatDescription?
        try checkStatus(CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: kCMVideoCodecType_AV1,
            width: Int32(width), height: Int32(height),
            extensions: nil, formatDescriptionOut: &description
        ))
        guard let description else { throw AOMVideoCodecError.unsupportedFormat }
        formatDescription = description
        var status: Int32 = 0
        context = hk_aom_encoder_create(UInt32(width), UInt32(height), try Self.bitrate(settings), fps,
                                        Int64((settings.maxKeyFrameIntervalDuration * 1_000_000).rounded()), Self.isConstantBitRate(settings) ? 1 : 0, &status)
        guard context != nil else { throw AOMVideoCodecError.codec(status) }

    }

    deinit {
        invalidate()
    }

    /// Updates bitrate and expected frame-rate hints without recreating the codec.
    /// - Parameter settings: The complete configuration. Only `bitRate` and `expectedFrameRate` may change.
    /// - Throws: ``AOMVideoCodecError/invalidSettings`` for other changes, or
    ///   ``AOMVideoCodecError/invalidSession`` after finishing or invalidation.
    public func update(_ settings: AOMVideoCodecSettings) throws {
        guard let context, !finished else { throw AOMVideoCodecError.invalidSession }
        guard settings.videoSize == self.settings.videoSize,
              settings.bitRateMode == self.settings.bitRateMode,
              settings.maxKeyFrameIntervalDuration == self.settings.maxKeyFrameIntervalDuration else {
            throw AOMVideoCodecError.invalidSettings
        }
        let fps = try Self.frameRate(settings)
        try checkCodec(hk_aom_encoder_update(context, try Self.bitrate(settings), fps))
        self.settings = settings
    }

    /// Compresses an 8-bit image sample synchronously.
    ///
    /// Accepts only video-range, 8-bit planar YUV 4:2:0 (I420), exactly matching
    /// the configured dimensions. The caller performs all color conversion, range
    /// normalization, and resizing before calling this method. No pixel conversion
    /// or scaling is performed here. Presentation timestamps must be numeric, epoch
    /// zero, and strictly increasing at microsecond precision. An invalid duration
    /// uses the expected frame rate. Serialize calls with all other operations.
    /// - Parameter sampleBuffer: A caller-prepared I420 image sample with a presentation timestamp.
    /// - Returns: Owned raw AV1 packets, with timing, keyframe attachments, and an
    ///   `av1C` configuration atom in the format description for muxing.
    ///   Packet storage remains valid after later calls or invalidation.
    /// - Throws: ``AOMVideoCodecError`` for an unsupported image, invalid timestamp,
    ///   inactive session, or a codec failure.
    public func encode(_ sampleBuffer: CMSampleBuffer) throws -> [CMSampleBuffer] {
        guard let context, !finished else { throw AOMVideoCodecError.invalidSession }
        guard let source = sampleBuffer.imageBuffer,
              CVPixelBufferGetPixelFormatType(source) == kCVPixelFormatType_420YpCbCr8Planar,
              CVPixelBufferGetWidth(source) == width, CVPixelBufferGetHeight(source) == height,
              CVPixelBufferGetPlaneCount(source) == 3 else {
            throw AOMVideoCodecError.unsupportedFormat
        }
        let pts = CMTimeConvertScale(sampleBuffer.presentationTimeStamp, timescale: 1_000_000, method: .default)
        guard pts.isNumeric, pts.epoch == 0, lastPTS.map({ pts.value > $0 }) ?? true else { throw AOMVideoCodecError.invalidTimestamp }
        let duration = CMTimeConvertScale(sampleBuffer.duration, timescale: 1_000_000, method: .default)
        let ticks = duration.isNumeric && duration.value > 0 ? duration.value : max(1, Int64((1_000_000 / (try Self.frameRate(settings))).rounded()))
        try checkStatus(CVPixelBufferLockBaseAddress(source, .readOnly))
        defer { CVPixelBufferUnlockBaseAddress(source, .readOnly) }
        var planes: [UnsafePointer<UInt8>] = []
        var strides: [Int32] = []
        for plane in 0..<3 {
            let planeWidth = plane == 0 ? width : width / 2
            let planeHeight = plane == 0 ? height : height / 2
            let stride = CVPixelBufferGetBytesPerRowOfPlane(source, plane)
            guard CVPixelBufferGetWidthOfPlane(source, plane) == planeWidth,
                  CVPixelBufferGetHeightOfPlane(source, plane) == planeHeight,
                  stride >= planeWidth, stride <= Int(Int32.max),
                  let base = CVPixelBufferGetBaseAddressOfPlane(source, plane) else {
                throw AOMVideoCodecError.unsupportedFormat
            }
            planes.append(UnsafePointer(base.assumingMemoryBound(to: UInt8.self)))
            strides.append(Int32(stride))
        }
        let start = DispatchTime.now().uptimeNanoseconds
        let status = hk_aom_encoder_encode(context, planes[0], strides[0], planes[1], strides[1],
                                            planes[2], strides[2], pts.value, UInt(ticks))
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
        try checkCodec(status)
        statistics.recordFrame(duration: elapsed)
        lastPTS = pts.value
        return try packets()
    }

    /// Drains pending packets and ends input for this encoder.
    /// - Returns: Remaining owned packets. Repeated calls return an empty array.
    /// - Throws: ``AOMVideoCodecError`` if invalidated or flushing fails.
    ///
    /// Create a new encoder to resume input. Call this before ``invalidate()`` to retain pending output.
    public func finish() throws -> [CMSampleBuffer] {
        guard let context else { throw AOMVideoCodecError.invalidSession }
        if finished { return [] }
        try checkCodec(hk_aom_encoder_flush(context))
        finished = true
        return try packets()
    }

    private func packets() throws -> [CMSampleBuffer] {
        var outputPackets: [CMSampleBuffer] = []
        var size = 0
        var outputPTS: Int64 = 0
        var outputDuration: UInt = 0
        var keyframe: Int32 = 0
        while let bytes = hk_aom_encoder_next_packet(context, &size, &outputPTS, &outputDuration, &keyframe) {
            let data = Data(bytes: bytes, count: size)
            if keyframe != 0, let record = try AOMAV1Configuration.record(in: data), record != configuration {
                var description: CMFormatDescription?
                try checkStatus(CMVideoFormatDescriptionCreate(allocator: kCFAllocatorDefault,
                    codecType: kCMVideoCodecType_AV1, width: Int32(width), height: Int32(height),
                    extensions: [kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms: ["av1C": record]] as CFDictionary,
                    formatDescriptionOut: &description))
                guard let description else { throw AOMVideoCodecError.unsupportedFormat }
                configuration = record
                formatDescription = description
            }
            guard configuration != nil else { throw AOMVideoCodecError.unsupportedFormat }
            guard let block = makeBlockBuffer(data) else {
                throw AOMVideoCodecError.coreMedia(kCMBlockBufferStructureAllocationFailedErr)
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
            guard let output else { throw AOMVideoCodecError.unsupportedFormat }
            if keyframe == 0, let attachments = CMSampleBufferGetSampleAttachmentsArray(output, createIfNecessary: true) {
                let values = attachments as NSArray
                if let first = values.firstObject as? NSMutableDictionary { first[kCMSampleAttachmentKey_NotSync] = true }
            }
            outputPackets.append(output)
        }
        statistics.recordOutput(packetCount: outputPackets.count, byteCount: outputPackets.reduce(UInt64(0)) { $0 + UInt64($1.totalSampleSize) })
        return outputPackets
    }

    /// Releases native resources. Repeated calls are safe; further encoding fails.
    public func invalidate() {
        hk_aom_destroy(context)
        context = nil
    }

    private static func bitrate(_ settings: AOMVideoCodecSettings) throws -> UInt32 {
        guard settings.bitRate > 0, settings.bitRate / 1000 <= Int(UInt32.max) else {
            throw AOMVideoCodecError.invalidSettings
        }
        return UInt32(max(1, settings.bitRate / 1000))
    }

    private static func frameRate(_ settings: AOMVideoCodecSettings) throws -> Double {
        let fps = settings.expectedFrameRate
        guard fps.isFinite, fps >= 0.001, fps <= 1_000_000 else { throw AOMVideoCodecError.invalidSettings }
        return fps
    }

    private static func isConstantBitRate(_ settings: AOMVideoCodecSettings) -> Bool {
        settings.bitRateMode == .constant
    }
}
