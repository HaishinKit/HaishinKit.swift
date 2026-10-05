import Foundation
import Testing

@testable import RTMPHaishinKit

@Suite struct RTMPUserControlMessageTests {
    // Regression: a truncated user control message (shorter than the 6-byte
    // event-type + value layout) must not trap on an out-of-bounds Data
    // subscript. Before the bounds guard this crashed the process from the
    // RTMP receive loop (EXC_BREAKPOINT in RTMPUserControlMessage.init).
    @Test func truncatedPayloadDoesNotCrash() {
        // messageLength 0 -> empty payload, position 0 == count 0, so
        // makeMessage() builds the message and runs the (previously
        // unguarded) decode against an empty buffer.
        let header = RTMPChunkMessageHeader(
            timestmap: 0,
            messageLength: 0,
            messageTypeId: RTMPMessageType.user.rawValue,
            messageStreamId: 0
        )
        let message = header.makeMessage() as? RTMPUserControlMessage
        #expect(message?.event == .unknown)
        #expect(message?.value == 0)
    }

    // A well-formed 6-byte user control message must still decode correctly
    // (2-byte event type + 4-byte big-endian value).
    @Test func wellFormedPayloadDecodes() {
        let buffer = RTMPChunkBuffer()
        // basic header (fmt 0, csid 2) | timestamp(3) | length(3)=6 |
        // typeId(1)=4 | streamId(4) | payload: event 0x0000 (streamBegin),
        // value 0x00000001.
        buffer.put(Data([2, 0, 0, 0, 0, 0, 6, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1]))
        do {
            let (chunkType, chunkStreamId) = try buffer.getBasicHeader()
            #expect(chunkType == .zero)
            #expect(chunkStreamId == 2)
            let header = RTMPChunkMessageHeader()
            try buffer.getMessageHeader(chunkType, messageHeader: header)
            let message = header.makeMessage() as? RTMPUserControlMessage
            #expect(message?.event == .streamBegin)
            #expect(message?.value == 1)
        } catch {
            Issue.record("unexpected error decoding user control message: \(error)")
        }
    }
}
