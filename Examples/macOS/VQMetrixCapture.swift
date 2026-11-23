import AVFoundation
import CoreImage
import CryptoKit
import HaishinKit

/// Owns all captured pixels; the mixer may reuse its source buffers immediately.
final class VQMetrixCapture: MediaMixerOutput, @unchecked Sendable {
    let videoTrackId: UInt8? = .max
    let audioTrackId: UInt8? = nil
    private let lock = NSLock()
    private let context = CIContext()
    private var frames: [CVPixelBuffer] = []
    private var lastArrival: ContinuousClock.Instant?
    private var stopped = false
    private var failure: String?
    static let width = 640
    static let height = 360
    static let fps = 15
    static let count = 45

    func selectTrack(_ id: UInt8?, mediaType: CMFormatDescription.MediaType) async { }
    func mixer(_ mixer: MediaMixer, didOutput buffer: AVAudioPCMBuffer, when: AVAudioTime) { }
    func mixer(_ mixer: MediaMixer, didOutput sampleBuffer: CMSampleBuffer) {
        append(sampleBuffer, at: .now)
    }

    /// Capture cadence follows callback arrival, independently of the source's timestamp timebase.
    func append(_ sampleBuffer: CMSampleBuffer, at arrival: ContinuousClock.Instant) {
        lock.lock()
        defer { lock.unlock() }
        guard !stopped, frames.count < Self.count,
              lastArrival.map({ $0.duration(to: arrival) >= .seconds(1.0 / Double(Self.fps) - 0.002) }) ?? true,
              let source = sampleBuffer.imageBuffer else { return }
        var pixel: CVPixelBuffer?
        let attributes: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [:]]
        guard CVPixelBufferCreate(nil, Self.width, Self.height,
                                  kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                                  attributes as CFDictionary, &pixel) == kCVReturnSuccess, let pixel else {
            failure = "Cannot allocate reference pixels."
            stopped = true
            return
        }
        let image = CIImage(cvPixelBuffer: source)
        let resized = image.transformed(by: CGAffineTransform(scaleX: Double(Self.width) / image.extent.width,
                                                               y: Double(Self.height) / image.extent.height))
        CVBufferSetAttachment(pixel, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(pixel, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(pixel, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2, .shouldPropagate)
        context.render(resized, to: pixel, bounds: CGRect(x: 0, y: 0, width: Self.width, height: Self.height),
                       colorSpace: CGColorSpace(name: CGColorSpace.itur_709)!)
        frames.append(pixel)
        lastArrival = arrival
    }

    func progress() throws -> Int {
        lock.lock()
        defer { lock.unlock() }
        if let failure { throw VQMetrixError(message: failure) }
        return frames.count
    }

    func stop() {
        lock.lock()
        stopped = true
        lock.unlock()
    }

    func package(in directory: URL, id: UUID, codec: VQMetrixCodec, bitrate: Int) async throws -> URL {
        stop()
        if let failure { throw VQMetrixError(message: failure) }
        guard frames.count == Self.count else { throw VQMetrixError(message: "Not enough video frames. Keep the preview running and try again.") }
        let movieName = "\(codec.rawValue)-\(bitrate).\(codec.fileExtension)"
        let movie = directory.appendingPathComponent(movieName)
        let reference = directory.appendingPathComponent("reference.y4m")
        FileManager.default.createFile(atPath: reference.path, contents: Data("YUV4MPEG2 W640 H360 F15:1 Ip A1:1 C420jpeg\n".utf8))
        let handle = try FileHandle(forWritingTo: reference)
        defer { try? handle.close() }
        try handle.seekToEnd()
        for frame in frames {
            try Task.checkCancellation()
            try writeReference(frame, to: handle)
        }
        if codec.isSoftware {
            try VQMetrixSoftwareEncoder.encode(frames, codec: codec, bitrate: bitrate, to: movie)
        } else {
            try await encodeMP4(to: movie, codec: codec, bitrate: bitrate)
        }
        let pts = (0..<Self.count).map { Int64($0) * 1_000_000 / 15 }
        let map: [String: Any] = ["referencePtsUs": pts, "captureTimestampsNs": [], "variants": [movieName: pts]]
        try JSONSerialization.data(withJSONObject: map).write(to: directory.appendingPathComponent("frame-map.json"))
        let names = ["reference.y4m", "frame-map.json", movieName]
        let files: [[String: Any]] = try names.map { name in
            let data = try Data(contentsOf: directory.appendingPathComponent(name))
            return ["path": name, "size": data.count, "sha256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()]
        }
        let manifest: [String: Any] = [
            "schema": "vqmetrix.capture.v1", "schemaVersion": 1, "runId": id.uuidString,
            "createdAt": ISO8601DateFormatter().string(from: Date()),
            "device": ["manufacturer": "Apple", "model": "Mac",
                       "osVersion": ProcessInfo.processInfo.operatingSystemVersionString,
                       "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"],
            "reference": ["file": "reference.y4m", "source": "macOS mixer snapshot (offline replay)",
                          "width": Self.width, "height": Self.height, "fpsNumerator": 15, "fpsDenominator": 1,
                          "frameCount": Self.count, "pixelFormat": "yuv420p", "bitDepth": 8,
                          "colorRange": "limited", "colorMatrix": "bt709", "frameMap": "frame-map.json"],
            "variants": [["file": movieName, "codec": codec.rawValue, "targetBitrate": bitrate,
                          "width": Self.width, "height": Self.height, "frameCount": Self.count, "codecName": codec == .av1 ? "libaom" : (codec.isSoftware ? "libvpx" : "VideoToolbox")]], "files": files
        ]
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys]).write(to: directory.appendingPathComponent("manifest.json"))
        let archive = directory.appendingPathComponent("capture.zip")
        try VQMetrixZIP.write(names: ["manifest.json"] + names, directory: directory, to: archive)
        return archive
    }

    private func encodeMP4(to movie: URL, codec: VQMetrixCodec, bitrate: Int) async throws {
        let writer = try AVAssetWriter(outputURL: movie, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: codec == .hevc ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
            AVVideoWidthKey: Self.width, AVVideoHeightKey: Self.height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: bitrate, AVVideoAllowFrameReorderingKey: false],
            AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                                       AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                                       AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2]
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        guard writer.canAdd(input) else { throw VQMetrixError(message: "Encoder unavailable.") }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? VQMetrixError(message: "Cannot start encoder.") }
        writer.startSession(atSourceTime: .zero)
        do {
            for (index, pixel) in frames.enumerated() {
                try Task.checkCancellation()
                let deadline = ContinuousClock.now + .seconds(15)
                while !input.isReadyForMoreMediaData {
                    guard writer.status == .writing, ContinuousClock.now < deadline else {
                        throw writer.error ?? VQMetrixError(message: "Encoder timed out.")
                    }
                    try await Task.sleep(for: .milliseconds(10))
                }
                guard adaptor.append(pixel, withPresentationTime: CMTime(value: Int64(index), timescale: 15)) else {
                    throw writer.error ?? VQMetrixError(message: "Cannot encode frame.")
                }
            }
            input.markAsFinished()
            await writer.finishWriting()
            guard writer.status == .completed else { throw writer.error ?? VQMetrixError(message: "Encoding failed.") }
        } catch {
            writer.cancelWriting()
            throw error
        }
    }

    private func writeReference(_ pixel: CVPixelBuffer, to handle: FileHandle) throws {
        CVPixelBufferLockBaseAddress(pixel, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixel, .readOnly) }
        try handle.write(contentsOf: Data("FRAME\n".utf8))
        let y = CVPixelBufferGetBaseAddressOfPlane(pixel, 0)!
        let uv = CVPixelBufferGetBaseAddressOfPlane(pixel, 1)!.assumingMemoryBound(to: UInt8.self)
        for row in 0..<Self.height {
            try handle.write(contentsOf: Data(bytes: y.advanced(by: row * CVPixelBufferGetBytesPerRowOfPlane(pixel, 0)), count: Self.width))
        }
        for component in 0..<2 {
            var plane = Data(capacity: Self.width * Self.height / 4)
            for row in 0..<Self.height / 2 {
                let offset = row * CVPixelBufferGetBytesPerRowOfPlane(pixel, 1)
                for column in 0..<Self.width / 2 { plane.append(uv[offset + column * 2 + component]) }
            }
            try handle.write(contentsOf: plane)
        }
    }
}

/// Stored ZIP entries avoid a separate runtime dependency or subprocess.
enum VQMetrixZIP {
    private static let crcTable: [UInt32] = (0..<256).map { value in
        var crc = UInt32(value)
        for _ in 0..<8 { crc = (crc >> 1) ^ (crc & 1 == 1 ? 0xedb88320 : 0) }
        return crc
    }
    static func write(names: [String], directory: URL, to output: URL) throws {
        var archive = Data()
        var central = Data()
        for name in names {
            try Task.checkCancellation()
            let bytes = try Data(contentsOf: directory.appendingPathComponent(name))
            let filename = Data(name.utf8)
            var crc: UInt32 = .max
            for byte in bytes { crc = (crc >> 8) ^ crcTable[Int((crc ^ UInt32(byte)) & 255)] }
            crc ^= .max
            let offset = UInt32(archive.count)
            archive.zipInteger(UInt32(0x04034b50))
            for value: UInt16 in [20, 0, 0, 0, 0] { archive.zipInteger(value) }
            for value in [crc, UInt32(bytes.count), UInt32(bytes.count)] { archive.zipInteger(value) }
            archive.zipInteger(UInt16(filename.count)); archive.zipInteger(UInt16(0))
            archive.append(filename); archive.append(bytes)
            central.zipInteger(UInt32(0x02014b50))
            for value: UInt16 in [20, 20, 0, 0, 0, 0] { central.zipInteger(value) }
            for value in [crc, UInt32(bytes.count), UInt32(bytes.count)] { central.zipInteger(value) }
            for value: UInt16 in [UInt16(filename.count), 0, 0, 0, 0] { central.zipInteger(value) }
            central.zipInteger(UInt32(0)); central.zipInteger(offset); central.append(filename)
        }
        let offset = UInt32(archive.count)
        archive.append(central)
        archive.zipInteger(UInt32(0x06054b50))
        for value: UInt16 in [0, 0, UInt16(names.count), UInt16(names.count)] { archive.zipInteger(value) }
        archive.zipInteger(UInt32(central.count)); archive.zipInteger(offset); archive.zipInteger(UInt16(0))
        try archive.write(to: output, options: .atomic)
    }
}

private extension Data {
    mutating func zipInteger<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}
