import AVFoundation
import Foundation
@testable import RTMPHaishinKit
import Testing

@Suite struct RTMPTimestampTests {
    @Test func acceptsZeroBasedFramesWithoutLosingTheFirstDelta() throws {
        var timestamp = RTMPTimestamp<CMTime>()
        #expect(try timestamp.update(.zero) == 0)
        #expect(throws: RTMPTimestamp<CMTime>.Error.self) { try timestamp.update(.zero) }
        #expect(try timestamp.update(CMTime(value: 1, timescale: 30)) == 33)
        #expect(try timestamp.update(CMTime(value: 2, timescale: 30)) == 33)
        timestamp.clear()
        #expect(try timestamp.update(.zero) == 0)
        #expect(try timestamp.update(CMTime(value: 1, timescale: 30)) == 33)
    }
    @Test func updateCMTime() throws {
        let times: [CMTime] = [
            CMTime(value: 286340171565869, timescale: 1000000000),
            CMTime(value: 286340204889958, timescale: 1000000000),
            CMTime(value: 286340238223357, timescale: 1000000000),
            CMTime(value: 286340271560111, timescale: 1000000000),
            CMTime(value: 286340304906325, timescale: 1000000000),
            CMTime(value: 286340338232723, timescale: 1000000000),
            CMTime(value: 286340338232723, timescale: 1000000000)
        ]
        var timestamp = RTMPTimestamp<CMTime>()
        #expect(try timestamp.update(times[0]) == 0)
        #expect(try timestamp.update(times[1]) == 33)
        #expect(try timestamp.update(times[2]) == 33)
        #expect(try timestamp.update(times[3]) == 33)
        #expect(try timestamp.update(times[4]) == 34)
        #expect(try timestamp.update(times[5]) == 33)
    }

    @Test func updateAVAudioTime() throws {
        let times: [AVAudioTime] = [
            .init(hostTime: 6901294874500, sampleTime: 13802589749, atRate: 48000),
            .init(hostTime: 6901295386500, sampleTime: 13802590773, atRate: 48000),
            .init(hostTime: 6901295898500, sampleTime: 13802591797, atRate: 48000),
            .init(hostTime: 6901296410500, sampleTime: 13802592821, atRate: 48000),
            .init(hostTime: 6901296922500, sampleTime: 13802593845, atRate: 48000),
            .init(hostTime: 6901297434500, sampleTime: 13802594869, atRate: 48000)
        ]
        var timestamp = RTMPTimestamp<AVAudioTime>()
        #expect(try timestamp.update(times[0]) == 0)
        #expect(try timestamp.update(times[1]) == 21)
        #expect(try timestamp.update(times[2]) == 21)
        #expect(try timestamp.update(times[3]) == 22)
        #expect(try timestamp.update(times[4]) == 21)
        #expect(try timestamp.update(times[5]) == 21)
    }
}
