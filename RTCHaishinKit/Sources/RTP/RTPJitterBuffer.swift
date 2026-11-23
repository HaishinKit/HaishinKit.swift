import Foundation

protocol RTPJitterBufferDelegate: AnyObject {
    func jitterBuffer(_ buffer: RTPJitterBuffer<Self>, sequenced: RTPPacket)
}

final class RTPJitterBuffer<T: RTPJitterBufferDelegate> {
    weak var delegate: T?

    private var buffer: [UInt16: RTPPacket] = [:]
    private var expectedSequence: UInt16?
    private let stalePacketCounts: Int = 4
    private var lastAccepted: TimeInterval?
    private var lastArrival: TimeInterval?
    private var restartPackets: [RTPPacket] = []
    private var lastRestartPacket: TimeInterval?

    func append(_ packet: RTPPacket, now: TimeInterval = Date.timeIntervalSinceReferenceDate) {
        // This is an inactivity heuristic, not a media clock. Discard probation
        // when wall time moves backwards rather than using system boot-time APIs.
        if let lastArrival, now < lastArrival {
            if let lastAccepted, now < lastAccepted { self.lastAccepted = now }
            restartPackets.removeAll(keepingCapacity: true)
            lastRestartPacket = nil
        } else if let lastRestartPacket, now - lastRestartPacket >= 1 {
            restartPackets.removeAll(keepingCapacity: true)
            self.lastRestartPacket = nil
        }
        lastArrival = now
        // RTP senders choose a random initial sequence number, not necessarily zero.
        let expected = expectedSequence ?? packet.sequenceNumber
        if Int16(bitPattern: packet.sequenceNumber &- expected) < 0 {
            // After a long interruption, modulo ordering cannot distinguish a new
            // run from old packets. Require inactivity and four consecutive packets;
            // keep the recent 3,000-packet late/duplicate window excluded.
            guard let lastAccepted, now - lastAccepted >= 1,
                  expected &- packet.sequenceNumber > 3_000 else { return }
            if let previous = restartPackets.last,
               previous.sequenceNumber &+ 1 == packet.sequenceNumber,
               let lastRestartPacket, now - lastRestartPacket < 1 {
                restartPackets.append(packet)
            } else {
                restartPackets = [packet]
            }
            lastRestartPacket = now
            guard restartPackets.count == stalePacketCounts else { return }
            buffer.removeAll(keepingCapacity: true)
            expectedSequence = restartPackets[0].sequenceNumber
            for candidate in restartPackets { buffer[candidate.sequenceNumber] = candidate }
        } else {
            expectedSequence = expected
        }
        restartPackets.removeAll(keepingCapacity: true)
        lastRestartPacket = nil
        lastAccepted = now
        buffer[packet.sequenceNumber] = packet
        if let expected = expectedSequence, buffer[expected] == nil, stalePacketCounts <= buffer.count {
            // Bound the queue and resume at the nearest available packet after a loss.
            expectedSequence = buffer.keys.min { ($0 &- expected) < ($1 &- expected) }
        }
        while let expected = expectedSequence, let next = buffer.removeValue(forKey: expected) {
            expectedSequence = expected &+ 1
            delegate?.jitterBuffer(self, sequenced: next)
        }
    }
}
