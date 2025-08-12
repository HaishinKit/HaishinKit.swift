import Foundation
import XCTest
import AVFoundation
@testable import HaishinKit

final class RTMPTimestampTests: XCTestCase {
    func testCMTime() {
        let times: [CMTime] = [
            CMTime(value: 286340171565869, timescale: 1000000000),
            CMTime(value: 286340204889958, timescale: 1000000000),
            CMTime(value: 286340238223357, timescale: 1000000000),
            CMTime(value: 286340271560111, timescale: 1000000000),
            CMTime(value: 286340304906325, timescale: 1000000000),
            CMTime(value: 286340338232723, timescale: 1000000000),
            CMTime(value: 286340338232723, timescale: 1000000000),
        ]
        var timestamp = RTMPTimestamp<CMTime>()
        XCTAssertEqual(0, try? timestamp.update(times[0]))
        XCTAssertEqual(33, try? timestamp.update(times[1]))
        XCTAssertEqual(33, try? timestamp.update(times[2]))
        XCTAssertEqual(33, try? timestamp.update(times[3]))
        XCTAssertEqual(34, try? timestamp.update(times[4]))
        XCTAssertEqual(33, try? timestamp.update(times[5]))
    }

    func testAVAudioTime() {
        let times: [AVAudioTime] = [
            .init(hostTime: 6901294874500, sampleTime: 13802589749, atRate: 48000),
            .init(hostTime: 6901295386500, sampleTime: 13802590773, atRate: 48000),
            .init(hostTime: 6901295898500, sampleTime: 13802591797, atRate: 48000),
            .init(hostTime: 6901296410500, sampleTime: 13802592821, atRate: 48000),
            .init(hostTime: 6901296922500, sampleTime: 13802593845, atRate: 48000),
            .init(hostTime: 6901297434500, sampleTime: 13802594869, atRate: 48000),
        ]
        var timestamp = RTMPTimestamp<AVAudioTime>()
        XCTAssertEqual(0, try? timestamp.update(times[0]))
        XCTAssertEqual(21, try? timestamp.update(times[1]))
        XCTAssertEqual(21, try? timestamp.update(times[2]))
        XCTAssertEqual(22, try? timestamp.update(times[3]))
        XCTAssertEqual(21, try? timestamp.update(times[4]))
        XCTAssertEqual(21, try? timestamp.update(times[5]))
    }
}
