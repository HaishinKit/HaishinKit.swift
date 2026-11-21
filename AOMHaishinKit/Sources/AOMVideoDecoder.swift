import CoreMedia
import CoreVideo
import Foundation
import AOMBridge

/// A synchronous decoder. Returned frames own their pixel storage; calls must be serialized.
public final class AOMVideoDecoder {
    private var context: OpaquePointer?
    private var pool: CVPixelBufferPool?
    private var dimensions: (width: Int, height: Int, fullRange: Bool)?

    /// Creates a decoder for 8-bit AV1 Main-profile packets.
    /// - Throws: ``AOMVideoCodecError`` if native decoder allocation fails.
    public init() throws {
        var status: Int32 = 0
        context = hk_aom_decoder_create(&status)
        guard context != nil else { throw AOMVideoCodecError.codec(status) }
    }

    deinit {
        invalidate()
    }

    /// Decodes a raw AV1 packet carried in a matching Core Media sample buffer.
    ///
    /// The caller demultiplexes container data before decoding. High-bit-depth output
    /// is unsupported. Container color metadata must be applied by the caller.
    /// Serialize calls with all other operations on this instance.
    /// - Parameter sampleBuffer: A nonempty raw packet with a matching video format
    ///   description and a numeric presentation timestamp.
    /// - Returns: Owned 8-bit NV12 frames preserving packet presentation time and duration.
    ///   Storage remains valid after later calls or invalidation. An empty array is allowed.
    /// - Throws: ``AOMVideoCodecError`` for invalid input, unsupported output,
    ///   an invalidated session, or a codec/Core Media failure.
    public func decode(_ sampleBuffer: CMSampleBuffer) throws -> [CMSampleBuffer] {
        guard let context else { throw AOMVideoCodecError.invalidSession }
        guard let description = sampleBuffer.formatDescription,
              CMFormatDescriptionGetMediaType(description) == kCMMediaType_Video,
              CMFormatDescriptionGetMediaSubType(description) == kCMVideoCodecType_AV1,
              sampleBuffer.presentationTimeStamp.isNumeric else { throw AOMVideoCodecError.unsupportedFormat }
        guard let data = sampleBuffer.dataBuffer else { throw AOMVideoCodecError.unsupportedFormat }
        let count = CMBlockBufferGetDataLength(data)
        guard count > 0, count <= Int(UInt32.max) else { throw AOMVideoCodecError.unsupportedFormat }
        var bytes = [UInt8](repeating: 0, count: count)
        try bytes.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { throw AOMVideoCodecError.unsupportedFormat }
            try checkStatus(CMBlockBufferCopyDataBytes(data, atOffset: 0, dataLength: count, destination: base))
        }
        try bytes.withUnsafeBufferPointer { buffer in
            try checkCodec(hk_aom_decoder_decode(context, buffer.baseAddress, UInt32(count)))
        }
        var frames: [CMSampleBuffer] = []
        var image = HKAOMImage()
        while true {
            let result = hk_aom_decoder_next_image(context, &image)
            guard result != 0 else { return frames }
            guard result > 0 else { throw AOMVideoCodecError.unsupportedFormat }
            let pixelBuffer = try makePixelBuffer(image)
            var format: CMFormatDescription?
            try checkStatus(CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescriptionOut: &format))
            guard let format else { throw AOMVideoCodecError.unsupportedFormat }
            var timing = CMSampleTimingInfo(duration: sampleBuffer.duration, presentationTimeStamp: sampleBuffer.presentationTimeStamp, decodeTimeStamp: .invalid)
            var output: CMSampleBuffer?
            try checkStatus(CMSampleBufferCreateReadyWithImageBuffer(
                allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer,
                formatDescription: format, sampleTiming: &timing, sampleBufferOut: &output
            ))
            guard let output else { throw AOMVideoCodecError.unsupportedFormat }
            frames.append(output)
        }
    }

    /// Releases native resources. Repeated calls are safe; further decoding fails.
    public func invalidate() {
        hk_aom_destroy(context)
        context = nil
        pool = nil
        dimensions = nil
    }

    private func makePixelBuffer(_ image: HKAOMImage) throws -> CVPixelBuffer {
        let width = Int(image.width)
        let height = Int(image.height)
        let fullRange = image.full_range != 0
        guard width > 0, height > 0, let sourceY = image.y, let sourceU = image.u, let sourceV = image.v else {
            throw AOMVideoCodecError.unsupportedFormat
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
        guard let pool else { throw AOMVideoCodecError.unsupportedFormat }
        var output: CVPixelBuffer?
        try checkStatus(CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &output))
        guard let output else { throw AOMVideoCodecError.unsupportedFormat }
        try checkStatus(CVPixelBufferLockBaseAddress(output, []))
        defer { CVPixelBufferUnlockBaseAddress(output, []) }
        guard let y = CVPixelBufferGetBaseAddressOfPlane(output, 0)?.assumingMemoryBound(to: UInt8.self),
              let uv = CVPixelBufferGetBaseAddressOfPlane(output, 1)?.assumingMemoryBound(to: UInt8.self) else {
            throw AOMVideoCodecError.unsupportedFormat
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
