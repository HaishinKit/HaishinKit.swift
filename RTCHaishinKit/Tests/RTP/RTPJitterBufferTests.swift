import AVFoundation
import Foundation
import Testing

@testable import RTCHaishinKit

@Suite struct RTPJitterBufferTests {
    final class Result: RTPJitterBufferDelegate {
        var count = 0
        var sequences: [UInt16] = []

        func jitterBuffer(_ buffer: RTPJitterBuffer<RTPJitterBufferTests.Result>, sequenced: RTPPacket) {
            count += 1
            sequences.append(sequenced.sequenceNumber)
        }
    }

    @Test func randomStartReordersAndIgnoresDuplicates() {
        let result = Result()
        let buffer = RTPJitterBuffer<Result>()
        buffer.delegate = result
        for sequence: UInt16 in [45000, 45002, 45001, 45001, 45003] {
            buffer.append(.init(version: 2, padding: false, extension: false, cc: 0, marker: false, payloadType: 111,
                                sequenceNumber: sequence, timestamp: 0, ssrc: 1, payload: Data([1])))
        }
        #expect(result.sequences == [45000, 45001, 45002, 45003])
    }

    @Test func sequenceWrapAndLargeLoss() {
        let result = Result()
        let buffer = RTPJitterBuffer<Result>()
        buffer.delegate = result
        for sequence: UInt16 in [65534, 0, 65535, 1, 1000, 1001, 1002, 1003] {
            buffer.append(.init(version: 2, padding: false, extension: false, cc: 0, marker: false, payloadType: 111,
                                sequenceNumber: sequence, timestamp: 0, ssrc: 1, payload: Data([1])))
        }
        #expect(result.sequences == [65534, 65535, 0, 1, 1000, 1001, 1002, 1003])
    }

    @Test func resumesAfterAnInactiveGapBeyondHalfTheSequenceSpace() {
        let result = Result()
        let buffer = RTPJitterBuffer<Result>()
        buffer.delegate = result
        let start: TimeInterval = 100
        buffer.append(Self.packet(1000), now: start)
        for sequence: UInt16 in [41000, 41001, 41002] {
            buffer.append(Self.packet(sequence), now: start + 2)
        }
        #expect(result.sequences == [1000])
        buffer.append(Self.packet(41003), now: start + 2)
        buffer.append(Self.packet(41004), now: start + 2)
        buffer.append(Self.packet(41003), now: start + 2)
        #expect(result.sequences == [1000, 41000, 41001, 41002, 41003, 41004])
    }

    @Test func rejectsLateRunsDuplicatesAndUnconfirmedRestarts() {
        let result = Result()
        let buffer = RTPJitterBuffer<Result>()
        buffer.delegate = result
        let start: TimeInterval = 100
        buffer.append(Self.packet(1000), now: start)
        for sequence: UInt16 in [41000, 41001, 41002, 41003] {
            buffer.append(Self.packet(sequence), now: start + 0.1)
        }
        for sequence: UInt16 in [997, 998, 999, 1000, 41000, 41000, 41002, 41003] {
            buffer.append(Self.packet(sequence), now: start + 2)
        }
        #expect(result.sequences == [1000])
        buffer.append(Self.packet(1001), now: start + 2)
        #expect(result.sequences == [1000, 1001])
    }

    @Test func restartConfirmationMustBeContiguousInTime() {
        let result = Result()
        let buffer = RTPJitterBuffer<Result>()
        buffer.delegate = result
        let start: TimeInterval = 100
        buffer.append(Self.packet(1000), now: start)
        for (index, sequence) in [UInt16(41000), 41001, 41002, 41003].enumerated() {
            buffer.append(Self.packet(sequence), now: start + Double(2 + index * 2))
        }
        #expect(result.sequences == [1000])
    }

    private static func packet(_ sequence: UInt16) -> RTPPacket {
        .init(version: 2, padding: false, extension: false, cc: 0, marker: false, payloadType: 111,
              sequenceNumber: sequence, timestamp: 0, ssrc: 1, payload: Data([1]))
    }

    @Test func backwardsWallClockDiscardsRestartProbation() {
        let result = Result()
        let buffer = RTPJitterBuffer<Result>()
        buffer.delegate = result
        buffer.append(Self.packet(1000), now: 100)
        buffer.append(Self.packet(41000), now: 102)
        buffer.append(Self.packet(41001), now: 102)
        buffer.append(Self.packet(41002), now: 101)
        buffer.append(Self.packet(41003), now: 101)
        #expect(result.sequences == [1000])
        buffer.append(Self.packet(41004), now: 101)
        buffer.append(Self.packet(41005), now: 101)
        #expect(result.sequences == [1000, 41002, 41003, 41004, 41005])

        buffer.append(Self.packet(10000), now: 90)
        buffer.append(Self.packet(10001), now: 90)
        buffer.append(Self.packet(10002), now: 90)
        buffer.append(Self.packet(10003), now: 90)
        #expect(result.sequences == [1000, 41002, 41003, 41004, 41005])
        for sequence: UInt16 in [10004, 10005, 10006, 10007] {
            buffer.append(Self.packet(sequence), now: 91)
        }
        #expect(result.sequences == [1000, 41002, 41003, 41004, 41005, 10004, 10005, 10006, 10007])
    }

    @Test func lostPacket()
 throws {
        let result = Result()
        let buffer = RTPJitterBuffer<Result>()
        buffer.delegate = result
        var packets: [RTPPacket] = []
        for i in 0...100 {
            packets.append(.init(version: 2, padding: false, extension: false, cc: 0, marker: false, payloadType: 0, sequenceNumber: UInt16(i), timestamp: UInt32(960 * (i + 1)), ssrc: 0, payload: Data()))
        }
        packets.remove(at: 30)
        packets.remove(at: 50)
        for packet in packets {
            buffer.append(packet)
        }

        #expect(result.count == 99)
    }
}
