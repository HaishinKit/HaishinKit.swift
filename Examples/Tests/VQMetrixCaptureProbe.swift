import AVFoundation
import Foundation
import HaishinKit
import CryptoKit

@main struct VQMetrixCaptureProbe {
    static func main() async throws {
        guard CommandLine.arguments.count == 2 else { fatalError("Pass an output directory for test fixtures.") }
        let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        for codec in VQMetrixCodec.allCases {
            let capture = VQMetrixCapture()
            let origin = ContinuousClock.now
            for index in 0..<180 {
                var pixel: CVPixelBuffer?
                CVPixelBufferCreate(nil, 640, 360, kCVPixelFormatType_32BGRA,
                                    [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pixel)
                CVPixelBufferLockBaseAddress(pixel!, [])
                let bytes = CVPixelBufferGetBaseAddress(pixel!)!.assumingMemoryBound(to: UInt8.self)
                for row in 0..<360 {
                    for column in 0..<640 {
                        let offset = row * CVPixelBufferGetBytesPerRow(pixel!) + column * 4
                        bytes[offset] = UInt8(column % 256)
                        bytes[offset + 1] = UInt8(row % 256)
                        bytes[offset + 2] = UInt8((index * 5) % 256)
                        bytes[offset + 3] = 255
                    }
                }
                CVPixelBufferUnlockBaseAddress(pixel!, [])
                var format: CMVideoFormatDescription?
                CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pixel!, formatDescriptionOut: &format)
                // Simulate a display's clock-unit mismatch: source PTS advances 400x too fast.
                var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 60), presentationTimeStamp: CMTime(value: Int64(index) * 400, timescale: 60), decodeTimeStamp: .invalid)
                var sample: CMSampleBuffer?
                CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: pixel!, formatDescription: format!, sampleTiming: &timing, sampleBufferOut: &sample)
                let arrival = origin.advanced(by: .nanoseconds(Int64(index) * 1_000_000_000 / 60))
                capture.append(sample!, at: arrival)
                let captured = try capture.progress()
                precondition(captured == min(45, index / 4 + 1), "Capture cadence followed source PTS instead of 60 Hz arrivals")
                // A mixer may immediately reuse the source storage after its callback.
                CVPixelBufferLockBaseAddress(pixel!, [])
                memset(CVPixelBufferGetBaseAddress(pixel!), 0, CVPixelBufferGetBytesPerRow(pixel!) * 360)
                CVPixelBufferUnlockBaseAddress(pixel!, [])
            }
            let folder = destination.appendingPathComponent(codec.rawValue)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let archive = try await capture.package(in: folder, id: UUID(), codec: codec, bitrate: 500_000)
            let metadata = try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("manifest.json"))) as! [String: Any]
            precondition((metadata["variants"] as! [[String: Any]])[0]["codec"] as? String == codec.rawValue)
            for payload in metadata["files"] as! [[String: Any]] {
                let data = try Data(contentsOf: folder.appendingPathComponent(payload["path"] as! String))
                precondition(payload["size"] as? Int == data.count)
                precondition(payload["sha256"] as? String == SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
            }
            let reference = try Data(contentsOf: folder.appendingPathComponent("reference.y4m"))
            let header = Data("YUV4MPEG2 W640 H360 F15:1 Ip A1:1 C420jpeg\n".utf8)
            precondition(reference.starts(with: header))
            precondition(reference.count == header.count + 45 * (6 + 640 * 360 * 3 / 2))
            let firstLuma = reference.subdata(in: (header.count + 6)..<(header.count + 6 + 640 * 360))
            precondition(Int(firstLuma.max()!) - Int(firstLuma.min()!) > 50, "Reference pixels were lost or overwritten")
            let zip = Process()
            zip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            zip.arguments = ["-t", archive.path]
            try zip.run(); zip.waitUntilExit()
            precondition(zip.terminationStatus == 0)
            print("PASS \(archive.path): 45 captured frames packaged")
        }
    }
}
