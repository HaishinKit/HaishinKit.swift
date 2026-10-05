import Foundation

protocol RTPJitterBufferDelegate: AnyObject {
    func jitterBuffer(_ buffer: RTPJitterBuffer<Self>, sequenced: RTPPacket)
}

final class RTPJitterBuffer<T: RTPJitterBufferDelegate> {
    weak var delegate: T?

    private var buffer: [UInt16: RTPPacket] = [:]
    private var expectedSequence: UInt16 = 0
    private var primed = false
    /// Reorder window before declaring the gap lost and skipping ahead. A
    /// fragmented IDR can span 20+ packets, so this must exceed one frame.
    private let maxBuffered = 32

    func append(_ packet: RTPPacket) {
        // RTP sequence numbers start at a RANDOM value (RFC 3550 §5.1); waiting
        // for sequence 0 stalls delivery for up to ~65k packets (minutes of
        // received-but-undecoded media). Prime from the first packet seen.
        if !primed {
            expectedSequence = packet.sequenceNumber
            primed = true
        }
        // Drop packets older than the playout point (wrap-aware signed distance);
        // they were already delivered or skipped. Without this, a late packet
        // sits in the dictionary forever and permanently inflates the count.
        if Int16(bitPattern: packet.sequenceNumber &- expectedSequence) < 0 {
            return
        }
        buffer[packet.sequenceNumber] = packet
        drain()
        // Gap recovery: a lost packet would otherwise block delivery forever
        // (the old "advance by 1 per append" crawl let expectedSequence run PAST
        // the live sequence, wedging the stream permanently). Once the reorder
        // window fills, jump straight to the oldest buffered packet and resume.
        if maxBuffered <= buffer.count {
            if let oldest = buffer.keys.min(by: {
                Int16(bitPattern: $0 &- expectedSequence) < Int16(bitPattern: $1 &- expectedSequence)
            }) {
                expectedSequence = oldest
                drain()
            }
        }
    }

    private func drain() {
        while let packet = buffer.removeValue(forKey: expectedSequence) {
            delegate?.jitterBuffer(self, sequenced: packet)
            expectedSequence &+= 1
        }
    }
}
