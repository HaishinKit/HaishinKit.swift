@preconcurrency import AVFoundation
import CoreImage
import CryptoKit
import HaishinKit

/// Captures one common reference, then replays it through each encoder setting.
actor TVQualityCapture: MediaMixerOutput {
    nonisolated let videoTrackId: UInt8? = UInt8.max
    nonisolated let audioTrackId: UInt8? = nil
    private let width = 640
    private let height = 360
    private let frameLimit = 45
    private var frames: [Data] = []
    private var timestamps: [Int64] = []
    private var lastTime = -Double.infinity
    private var capturing = false
    private let context = CIContext(options: [.cacheIntermediates: false])

    func selectTrack(_ id: UInt8?, mediaType: CMFormatDescription.MediaType) async {}
    nonisolated func mixer(_ mixer: MediaMixer, didOutput buffer: AVAudioPCMBuffer, when: AVAudioTime) {}
    nonisolated func mixer(_ mixer: MediaMixer, didOutput buffer: CMSampleBuffer) {
        Task { await append(buffer) }
    }

    func capture() async throws -> [Data] {
        frames.removeAll()
        timestamps.removeAll()
        lastTime = -.infinity
        capturing = true
        defer { capturing = false }
        for _ in 0..<200 {
            try Task.checkCancellation()
            if frames.count == frameLimit { return frames }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw QualityError("No complete video capture. Select a working source and retry.")
    }

    private func append(_ sample: CMSampleBuffer) {
        guard capturing, frames.count < frameLimit, let source = sample.imageBuffer else { return }
        let time = sample.presentationTimeStamp.seconds
        guard time.isFinite, time - lastTime >= 1.0 / 15 - 0.002 else { return }
        var image: CVPixelBuffer?
        guard
            CVPixelBufferCreate(
                nil, width, height, kCVPixelFormatType_32BGRA,
                [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &image) == kCVReturnSuccess,
            let image
        else { return }
        let input = CIImage(cvPixelBuffer: source)
        // Both the encoder and reference use these exact, normalized BT.709 pixels.
        let scaled = input.transformed(by: .init(scaleX: CGFloat(width) / input.extent.width, y: CGFloat(height) / input.extent.height))
        context.render(
            scaled, to: image, bounds: CGRect(x: 0, y: 0, width: width, height: height),
            colorSpace: CGColorSpace(name: CGColorSpace.itur_709)!)
        CVPixelBufferLockBaseAddress(image, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(image, .readOnly) }
        guard let pixels = CVPixelBufferGetBaseAddress(image)?.assumingMemoryBound(to: UInt8.self) else { return }
        let rowStride = CVPixelBufferGetBytesPerRow(image)
        var planar = Data(count: width * height * 3 / 2)
        planar.withUnsafeMutableBytes { raw in
            let out = raw.bindMemory(to: UInt8.self)
            for y in 0..<height {
                for x in 0..<width {
                    let p = pixels.advanced(by: y * rowStride + x * 4)
                    let r = Double(p[2])
                    let g = Double(p[1])
                    let b = Double(p[0])
                    out[y * width + x] = UInt8(clamping: Int((16 + (0.2126 * r + 0.7152 * g + 0.0722 * b) * 219 / 255).rounded()))
                }
            }
            for y in stride(from: 0, to: height, by: 2) {
                for x in stride(from: 0, to: width, by: 2) {
                    var r = 0.0
                    var g = 0.0
                    var b = 0.0
                    for dy in 0..<2 {
                        for dx in 0..<2 {
                            let p = pixels.advanced(by: (y + dy) * rowStride + (x + dx) * 4)
                            r += Double(p[2]) / 4
                            g += Double(p[1]) / 4
                            b += Double(p[0]) / 4
                        }
                    }
                    let index = y / 2 * (width / 2) + x / 2
                    out[width * height + index] = UInt8(clamping: Int((128 + (-0.114572 * r - 0.385428 * g + 0.5 * b) * 224 / 255).rounded()))
                    out[width * height * 5 / 4 + index] = UInt8(clamping: Int((128 + (0.5 * r - 0.454153 * g - 0.045847 * b) * 224 / 255).rounded()))
                }
            }
        }
        frames.append(planar)
        timestamps.append(Int64(time * 1_000_000_000))
        lastTime = time
    }

    func makePackage(frames: [Data], directory: URL, runID: UUID, source: String, bitrates: [Int]) async throws -> URL {
        let reference = directory.appendingPathComponent("reference.y4m")
        FileManager.default.createFile(atPath: reference.path, contents: Data("YUV4MPEG2 W640 H360 F15:1 Ip A1:1 C420jpeg XCOLORRANGE=LIMITED\n".utf8))
        let handle = try FileHandle(forWritingTo: reference)
        try handle.seekToEnd()
        for frame in frames {
            try handle.write(contentsOf: Data("FRAME\n".utf8))
            try handle.write(contentsOf: frame)
        }
        try handle.close()
        let pts = frames.indices.map { Int64($0) * 1_000_000 / 15 }
        var variants: [[String: Any]] = []
        var map: [String: [Int64]] = [:]
        for bitrate in bitrates {
            try Task.checkCancellation()
            let name = "h264-\(bitrate).mp4"
            let output = directory.appendingPathComponent(name)
            try await encode(frames, bitrate: bitrate, output: output)
            map[name] = pts
            variants.append([
                "file": name, "codec": "h264", "targetBitrate": bitrate, "frameCount": frames.count,
                "width": width, "height": height,
            ])
        }
        let frameMap: [String: Any] = ["referencePtsUs": pts, "captureTimestampsNs": source == "continuity-camera" ? timestamps : [], "variants": map]
        try JSONSerialization.data(withJSONObject: frameMap, options: [.sortedKeys]).write(to: directory.appendingPathComponent("frame-map.json"))
        let names = ["reference.y4m", "frame-map.json"] + bitrates.map { "h264-\($0).mp4" }
        let payloads = try names.map { name -> [String: Any] in
            let data = try Data(contentsOf: directory.appendingPathComponent(name))
            return ["path": name, "size": data.count, "sha256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()]
        }
        let manifest: [String: Any] = [
            "schema": "vqmetrix.capture.v1", "schemaVersion": 1, "runId": runID.uuidString,
            "createdAt": ISO8601DateFormatter().string(from: Date()),
            "device": ["manufacturer": "Apple", "model": "Apple TV", "platform": "tvOS", "osVersion": ProcessInfo.processInfo.operatingSystemVersionString],
            "reference": [
                "file": "reference.y4m", "source": source, "width": width, "height": height,
                "fpsNumerator": 15, "fpsDenominator": 1, "frameCount": frames.count, "pixelFormat": "yuv420p", "bitDepth": 8,
                "colorRange": "limited", "colorMatrix": "bt709", "sensorOrientation": 0, "frameMap": "frame-map.json",
            ],
            "variants": variants, "files": payloads,
        ]
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys]).write(to: directory.appendingPathComponent("manifest.json"))
        let zip = directory.appendingPathComponent("\(runID.uuidString).zip")
        try TVQualityZIP.write(names: ["manifest.json"] + names, directory: directory, output: zip)
        self.frames.removeAll()
        return zip
    }

    private func encode(_ frames: [Data], bitrate: Int, output: URL) async throws {
        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: bitrate, AVVideoAllowFrameReorderingKey: false, AVVideoExpectedSourceFrameRateKey: 15,
                ],
                AVVideoColorPropertiesKey: [
                    AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                    AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2, AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
                ],
            ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            ])
        guard writer.canAdd(input) else { throw QualityError("H.264 encoding is unavailable.") }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? QualityError("Cannot start encoding.") }
        defer { if writer.status == .writing { writer.cancelWriting() } }
        writer.startSession(atSourceTime: .zero)
        for (index, frame) in frames.enumerated() {
            while !input.isReadyForMoreMediaData {
                try Task.checkCancellation()
                guard writer.status == .writing else { throw writer.error ?? QualityError("Encoder stopped.") }
                try await Task.sleep(for: .milliseconds(5))
            }
            try Task.checkCancellation()
            var pixel: CVPixelBuffer?
            guard let pool = adaptor.pixelBufferPool, CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixel) == kCVReturnSuccess, let pixel else {
                throw QualityError("Cannot allocate encoder pixels.")
            }
            CVBufferSetAttachment(pixel, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)
            CVBufferSetAttachment(pixel, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
            CVBufferSetAttachment(pixel, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2, .shouldPropagate)
            CVPixelBufferLockBaseAddress(pixel, [])
            frame.withUnsafeBytes { raw in
                let bytes = raw.bindMemory(to: UInt8.self)
                let y = CVPixelBufferGetBaseAddressOfPlane(pixel, 0)!.assumingMemoryBound(to: UInt8.self)
                let uv = CVPixelBufferGetBaseAddressOfPlane(pixel, 1)!.assumingMemoryBound(to: UInt8.self)
                for row in 0..<height {
                    memcpy(y.advanced(by: row * CVPixelBufferGetBytesPerRowOfPlane(pixel, 0)), bytes.baseAddress!.advanced(by: row * width), width)
                }
                for row in 0..<height / 2 {
                    for col in 0..<width / 2 {
                        let target = row * CVPixelBufferGetBytesPerRowOfPlane(pixel, 1) + col * 2
                        uv[target] = bytes[width * height + row * width / 2 + col]
                        uv[target + 1] = bytes[width * height * 5 / 4 + row * width / 2 + col]
                    }
                }
            }
            CVPixelBufferUnlockBaseAddress(pixel, [])
            guard adaptor.append(pixel, withPresentationTime: CMTime(value: Int64(index) * 1_000_000 / 15, timescale: 1_000_000)) else {
                throw writer.error ?? QualityError("Cannot encode frame.")
            }
        }
        writer.endSession(atSourceTime: CMTime(value: Int64(frames.count), timescale: 15))
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? QualityError("Encoding failed.") }
    }
}

struct QualityError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
