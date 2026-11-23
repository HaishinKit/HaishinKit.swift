import AOMHaishinKit
import AVFoundation
import VPXHaishinKit

enum VQMetrixCodec: String, CaseIterable, Identifiable, Sendable {
    case h264, hevc, av1, vp8, vp9
    var id: Self { self }
    var label: String {
        switch self {
        case .h264: return "H.264"
        case .hevc: return "HEVC"
        case .av1: return "AV1 (software)"
        case .vp8: return "VP8 (software)"
        case .vp9: return "VP9 (software)"
        }
    }
    var isSoftware: Bool { self == .av1 || self == .vp8 || self == .vp9 }
    var fileExtension: String { isSoftware ? "ivf" : "mp4" }
    var fourCC: String {
        switch self {
        case .av1: return "AV01"
        case .vp8: return "VP80"
        case .vp9: return "VP90"
        default: return ""
        }
    }
}

/// Runs synchronously on the packaging task, with all codec instances confined to that executor.
enum VQMetrixSoftwareEncoder {
    static func encode(_ frames: [CVPixelBuffer], codec: VQMetrixCodec, bitrate: Int, to url: URL) throws {
        let size = CGSize(width: VQMetrixCapture.width, height: VQMetrixCapture.height)
        let aom = try codec == .av1 ? AOMVideoEncoder(settings: .init(videoSize: size, bitRate: bitrate, expectedFrameRate: 15)) : nil
        let vpx = try codec == .av1 ? nil : VPXVideoEncoder(settings: .init(videoSize: size, bitRate: bitrate, expectedFrameRate: 15, format: codec == .vp8 ? .vp8 : .vp9))
        defer { aom?.invalidate(); vpx?.invalidate() }
        var packets: [CMSampleBuffer] = []
        for (index, frame) in frames.enumerated() {
            try Task.checkCancellation()
            let sample = try sample(frame, index: index)
            if let aom { packets += try aom.encode(sample) }
            if let vpx { packets += try vpx.encode(sample) }
        }
        if let aom { packets += try aom.finish() }
        if let vpx { packets += try vpx.finish() }
        guard packets.count == frames.count else { throw VQMetrixError(message: "Software encoder output count differs from the reference.") }
        // IVF uses a microsecond timebase, matching the manifest's integer CFR timestamps.
        var data = Data("DKIF".utf8)
        data.ivfInteger(UInt16(0)); data.ivfInteger(UInt16(32))
        data.append(Data(codec.fourCC.utf8))
        data.ivfInteger(UInt16(VQMetrixCapture.width)); data.ivfInteger(UInt16(VQMetrixCapture.height))
        data.ivfInteger(UInt32(1_000_000)); data.ivfInteger(UInt32(1))
        data.ivfInteger(UInt32(packets.count)); data.ivfInteger(UInt32(0))
        for (index, packet) in packets.enumerated() {
            try Task.checkCancellation()
            let pts = Int64(index) * 1_000_000 / 15
            guard packet.presentationTimeStamp == CMTime(value: pts, timescale: 1_000_000),
                  let block = packet.dataBuffer else { throw VQMetrixError(message: "Software encoder output timing differs from the reference.") }
            let length = CMBlockBufferGetDataLength(block)
            guard length > 0, length <= Int(UInt32.max) else { throw VQMetrixError(message: "Invalid encoded packet size.") }
            var bytes = Data(count: length)
            let status = bytes.withUnsafeMutableBytes {
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: $0.baseAddress!)
            }
            guard status == noErr else { throw VQMetrixError(message: "Cannot copy compressed packet.") }
            data.ivfInteger(UInt32(length)); data.ivfInteger(UInt64(pts)); data.append(bytes)
        }
        try data.write(to: url, options: .atomic)
    }

    /// Deinterleave NV12 without changing the pixels used by the Y4M reference.
    private static func sample(_ source: CVPixelBuffer, index: Int) throws -> CMSampleBuffer {
        let width = VQMetrixCapture.width, height = VQMetrixCapture.height
        var image: CVPixelBuffer?
        guard CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_420YpCbCr8Planar, nil, &image) == kCVReturnSuccess,
              let image else { throw VQMetrixError(message: "Cannot allocate I420 pixels.") }
        CVPixelBufferLockBaseAddress(source, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(source, .readOnly) }
        CVPixelBufferLockBaseAddress(image, [])
        defer { CVPixelBufferUnlockBaseAddress(image, []) }
        let y = CVPixelBufferGetBaseAddressOfPlane(source, 0)!
        let uv = CVPixelBufferGetBaseAddressOfPlane(source, 1)!.assumingMemoryBound(to: UInt8.self)
        let outputY = CVPixelBufferGetBaseAddressOfPlane(image, 0)!
        let u = CVPixelBufferGetBaseAddressOfPlane(image, 1)!.assumingMemoryBound(to: UInt8.self)
        let v = CVPixelBufferGetBaseAddressOfPlane(image, 2)!.assumingMemoryBound(to: UInt8.self)
        for row in 0..<height {
            memcpy(outputY.advanced(by: row * CVPixelBufferGetBytesPerRowOfPlane(image, 0)),
                   y.advanced(by: row * CVPixelBufferGetBytesPerRowOfPlane(source, 0)), width)
        }
        for row in 0..<height / 2 {
            for column in 0..<width / 2 {
                let offset = row * CVPixelBufferGetBytesPerRowOfPlane(source, 1) + column * 2
                u[row * CVPixelBufferGetBytesPerRowOfPlane(image, 1) + column] = uv[offset]
                v[row * CVPixelBufferGetBytesPerRowOfPlane(image, 2) + column] = uv[offset + 1]
            }
        }
        CVBufferPropagateAttachments(source, image)
        var description: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: image, formatDescriptionOut: &description) == noErr,
              let description else { throw VQMetrixError(message: "Cannot describe I420 pixels.") }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 15),
                                       presentationTimeStamp: CMTime(value: Int64(index) * 1_000_000 / 15, timescale: 1_000_000),
                                       decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: image, formatDescription: description,
                                                      sampleTiming: &timing, sampleBufferOut: &sample) == noErr,
              let sample else { throw VQMetrixError(message: "Cannot create I420 sample.") }
        return sample
    }
}

private extension Data {
    mutating func ivfInteger<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}
