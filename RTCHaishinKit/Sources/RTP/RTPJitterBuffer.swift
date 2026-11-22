import Foundation

protocol RTPJitterBufferDelegate: AnyObject {
    func jitterBuffer(_ buffer: RTPJitterBuffer<Self>, sequenced: RTPPacket)
}

final class RTPJitterBuffer<T: RTPJitterBufferDelegate> {
    weak var delegate: T?

    private var buffer: [UInt16: RTPPacket] = [:]
    private var expectedSequence: UInt16?
    private let stalePacketCounts: Int = 4

    func append(_ packet: RTPPacket) {
        // RTP senders choose a random initial sequence number, not necessarily zero.
        let expected = expectedSequence ?? packet.sequenceNumber
        guard Int16(bitPattern: packet.sequenceNumber &- expected) >= 0 else { return }
        expectedSequence = expected
        buffer[packet.sequenceNumber] = packet
        if buffer[expected] == nil, stalePacketCounts <= buffer.count {
            // Bound the queue and resume at the nearest available packet after a loss.
            expectedSequence = buffer.keys.min { ($0 &- expected) < ($1 &- expected) }
        }
        while let expected = expectedSequence, let next = buffer.removeValue(forKey: expected) {
            expectedSequence = expected &+ 1
            delegate?.jitterBuffer(self, sequenced: next)
        }
    }
}
