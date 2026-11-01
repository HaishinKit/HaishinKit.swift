@preconcurrency import AVFoundation
import Foundation
import Testing

@testable import HaishinKit

@Suite struct StreamRecorderTests {
    @Test func startRunning_nil() async throws {
        let recorder = StreamRecorder()
        try await recorder.startRecording(nil)
        let moviesDirectory = await recorder.moviesDirectory
        // $moviesDirectory/B644F60F-0959-4F54-9D14-7F9949E02AD8.mp4
        #expect(((await recorder.outputURL?.path.contains(moviesDirectory.path())) != nil))
    }

    @Test func startRunning_fileName() async throws {
        let recorder = StreamRecorder()
        try? await recorder.startRecording(URL(string: "dir/sample.mp4"))
        _ = await recorder.moviesDirectory
        // $moviesDirectory/dir/sample.mp4
        #expect(((await recorder.outputURL?.path.contains("dir/sample.mp4")) != nil))
    }

    @Test func startRunning_fullPath() async {
        let recorder = StreamRecorder()
        let fullPath = await recorder.moviesDirectory.appendingPathComponent("sample.mp4")
        // $moviesDirectory/sample.mp4
        try? await recorder.startRecording(fullPath)
        #expect(await recorder.outputURL == fullPath)
    }

    @Test func startRunning_dir() async {
        let recorder = StreamRecorder()
        try? await recorder.startRecording(URL(string: "dir"))
        // $moviesDirectory/dir/33FA7D32-E0A8-4E2C-9980-B54B60654044.mp4
        #expect(((await recorder.outputURL?.path.contains("dir")) != nil))
    }

    @Test func startRunning_fileAlreadyExists() async {
        let recorder = StreamRecorder()
        let filePath = await recorder.moviesDirectory.appendingPathComponent("duplicate-file.mp4")
        FileManager.default.createFile(atPath: filePath.path, contents: nil)
        do {
            try await recorder.startRecording(filePath)
            fatalError()
        } catch {
            try? FileManager.default.removeItem(atPath: filePath.path)
        }
    }

    @Test(arguments: [([0, 1, 2, 3], [0, 1, 2, 3]), ([0, 2, 1, 1, 2, 3], [0, 2, 3])])
    func recording_dropsOutOfOrderVideo(timestamps: [Int], expected: [Int]) async throws {
        let recorder = StreamRecorder()
        let settings: [AVMediaType: [String: any Sendable]] = [
            .video: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 64,
                AVVideoHeightKey: 64,
                AVVideoCompressionPropertiesKey: [AVVideoAllowFrameReorderingKey: false]
            ]
        ]
        // Reuse the recorder to verify the previous recording's timestamp is cleared.
        for _ in 0..<2 {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
            defer { try? FileManager.default.removeItem(at: url) }
            try await recorder.startRecording(url, settings: settings)
            let errors = await recorder.error
            let errorCount = Task {
                var count = 0
                for await _ in errors {
                    count += 1
                }
                return count
            }
            for timestamp in timestamps {
                let sampleBuffer = try #require(CMVideoSampleBufferFactory.makeSampleBuffer(width: 64, height: 64))
                var timing = CMSampleTimingInfo(
                    duration: CMTime(value: 1, timescale: 30),
                    presentationTimeStamp: CMTime(value: Int64(timestamp), timescale: 30),
                    decodeTimeStamp: .invalid
                )
                var timedSampleBuffer: CMSampleBuffer?
                #expect(CMSampleBufferCreateCopyWithNewTiming(
                    allocator: kCFAllocatorDefault,
                    sampleBuffer: sampleBuffer,
                    sampleTimingEntryCount: 1,
                    sampleTimingArray: &timing,
                    sampleBufferOut: &timedSampleBuffer
                ) == noErr)
                await recorder.append(try #require(timedSampleBuffer))
                // Pace input so encoder backpressure does not drop frames under test.
                try await Task.sleep(nanoseconds: 30_000_000)
            }
            #expect(try await recorder.stopRecording() == url)
            #expect(await errorCount.value == 0)

            let asset = AVURLAsset(url: url)
            let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            reader.add(output)
            #expect(reader.startReading())
            var recordedTimestamps: [CMTime] = []
            while let sampleBuffer = output.copyNextSampleBuffer() {
                if sampleBuffer.numSamples > 0 {
                    recordedTimestamps.append(sampleBuffer.presentationTimeStamp)
                }
            }
            #expect(reader.status == .completed)
            #expect(recordedTimestamps == expected.map { CMTime(value: Int64($0), timescale: 30) })
        }
    }

    @Test func recording_dropsOutOfOrderAudio() async throws {
        let recorder = StreamRecorder()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
        defer { try? FileManager.default.removeItem(at: url) }
        try await recorder.startRecording(url, settings: [
            .audio: [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
        ])
        let errors = await recorder.error
        let errorCount = Task {
            var count = 0
            for await _ in errors {
                count += 1
            }
            return count
        }
        for timestamp in [0, 2, 1, 1, 2, 3] {
            let sampleBuffer = try #require(CMAudioSampleBufferFactory.makeSilence(
                48000,
                presentaionTimeStamp: CMTime(value: Int64(timestamp * 1024), timescale: 48000)
            ))
            await recorder.append(sampleBuffer)
            try await Task.sleep(nanoseconds: 30_000_000)
        }
        #expect(try await recorder.stopRecording() == url)
        #expect(await errorCount.value == 0)

        let asset = AVURLAsset(url: url)
        let track = try #require(try await asset.loadTracks(withMediaType: .audio).first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)
        #expect(reader.startReading())
        var sampleCount = 0
        while let sampleBuffer = output.copyNextSampleBuffer() {
            sampleCount += sampleBuffer.numSamples
        }
        #expect(reader.status == .completed)
        #expect(sampleCount == 3 * 1024)
    }
}
