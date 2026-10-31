import Foundation
import libsrt

/// A snapshot of SRT socket performance statistics.
///
/// This structure wraps the library’s `CBytePerfMon` values. Fields ending in
/// `Total` are cumulative; other counters describe the library’s measurement interval.
/// Rates, buffer sizes, and timing values describe the sampled state.
public struct SRTPerformanceData: Sendable {
    /// The elapsed time since the socket started, in milliseconds.
    public let msTimeStamp: Int64
    /// The total number of sent data packets, including retransmissions.
    public let pktSentTotal: Int64
    /// The total number of received packets.
    public let pktRecvTotal: Int64
    /// The total number of lost packets (sender side).
    public let pktSndLossTotal: Int32
    /// The total number of lost packets (receiver side).
    public let pktRcvLossTotal: Int32
    /// The total number of retransmitted packets.
    public let pktRetransTotal: Int32
    /// The total number of sent ACK packets.
    public let pktSentACKTotal: Int32
    /// The total number of received ACK packets.
    public let pktRecvACKTotal: Int32
    /// The total number of sent NAK packets.
    public let pktSentNAKTotal: Int32
    /// The total number of received NAK packets.
    public let pktRecvNAKTotal: Int32
    /// The cumulative time spent sending data, excluding idle time, in microseconds.
    public let usSndDurationTotal: Int64
    /// The number of packets dropped because they were too late to send.
    public let pktSndDropTotal: Int32
    /// The number of packets dropped because they were too late to play.
    public let pktRcvDropTotal: Int32
    /// The number of packets that could not be decrypted.
    public let pktRcvUndecryptTotal: Int32
    /// The total number of sent data bytes, including retransmissions.
    public let byteSentTotal: UInt64
    /// The total number of received bytes.
    public let byteRecvTotal: UInt64
    /// The total number of lost bytes.
    public let byteRcvLossTotal: UInt64
    /// The total number of retransmitted bytes.
    public let byteRetransTotal: UInt64
    /// The number of bytes dropped because they were too late to send.
    public let byteSndDropTotal: UInt64
    /// The number of bytes dropped because they were too late to play, estimated from the average packet size.
    public let byteRcvDropTotal: UInt64
    /// The number of bytes that could not be decrypted.
    public let byteRcvUndecryptTotal: UInt64
    /// The number of sent data packets, including retransmissions.
    public let pktSent: Int64
    /// The number of received packets.
    public let pktRecv: Int64
    /// The number of lost packets (sender side).
    public let pktSndLoss: Int32
    /// The number of lost packets (receiver side).
    public let pktRcvLoss: Int32
    /// The number of retransmitted packets.
    public let pktRetrans: Int32
    /// The number of retransmitted packets received.
    public let pktRcvRetrans: Int32
    /// The number of sent ACK packets.
    public let pktSentACK: Int32
    /// The number of received ACK packets.
    public let pktRecvACK: Int32
    /// The number of sent NAK packets.
    public let pktSentNAK: Int32
    /// The number of received NAK packets.
    public let pktRecvNAK: Int32
    /// The sending rate, in megabits per second.
    public let mbpsSendRate: Double
    /// The receiving rate, in megabits per second.
    public let mbpsRecvRate: Double
    /// The time spent sending data during the measurement interval, excluding idle time, in microseconds.
    public let usSndDuration: Int64
    /// The sequence-number distance of reordered received packets.
    public let pktReorderDistance: Int32
    /// The average delay of late packets whose sequence numbers precede the acknowledged position.
    public let pktRcvAvgBelatedTime: Double
    /// The number of received packets ignored because they arrived too late.
    public let pktRcvBelated: Int64
    /// The number of packets dropped because they were too late to send.
    public let pktSndDrop: Int32
    /// The number of packets dropped because they were too late to play.
    public let pktRcvDrop: Int32
    /// The number of packets that could not be decrypted.
    public let pktRcvUndecrypt: Int32
    /// The number of sent data bytes, including retransmissions.
    public let byteSent: UInt64
    /// The number of received bytes.
    public let byteRecv: UInt64
    /// The number of lost bytes reported by the receiver.
    public let byteRcvLoss: UInt64
    /// The number of retransmitted bytes.
    public let byteRetrans: UInt64
    /// The number of bytes dropped because they were too late to send.
    public let byteSndDrop: UInt64
    /// The number of bytes dropped because they were too late to play, estimated from the average packet size.
    public let byteRcvDrop: UInt64
    /// The number of bytes that could not be decrypted.
    public let byteRcvUndecrypt: UInt64
    /// The packet sending period, in microseconds.
    public let usPktSndPeriod: Double
    /// The flow window size, in number of packets.
    public let pktFlowWindow: Int32
    /// The congestion window size, in number of packets.
    public let pktCongestionWindow: Int32
    /// The number of packets in flight.
    public let pktFlightSize: Int32
    /// The round-trip time, in milliseconds.
    public let msRTT: Double
    /// The estimated available bandwidth, in megabits per second.
    public let mbpsBandwidth: Double
    /// The available space in the send buffer, in bytes.
    public let byteAvailSndBuf: Int32
    /// The available space in the receive buffer, in bytes.
    public let byteAvailRcvBuf: Int32
    /// The transmission bandwidth limit, in megabits per second.
    public let mbpsMaxBW: Double
    /// The maximum transmission unit, in bytes.
    public let byteMSS: Int32
    /// The number of unacknowledged packets in the send buffer.
    public let pktSndBuf: Int32
    /// The number of unacknowledged bytes in the send buffer.
    public let byteSndBuf: Int32
    /// The time span of unacknowledged data in the send buffer, in milliseconds.
    public let msSndBuf: Int32
    /// The sender’s timestamp-based packet delivery delay, in milliseconds.
    public let msSndTsbPdDelay: Int32
    /// The number of packets awaiting delivery in the receive buffer.
    public let pktRcvBuf: Int32
    /// The number of bytes awaiting delivery in the receive buffer.
    public let byteRcvBuf: Int32
    /// The time span of data awaiting delivery in the receive buffer, in milliseconds.
    public let msRcvBuf: Int32
    /// The receiver’s timestamp-based packet delivery delay, in milliseconds.
    public let msRcvTsbPdDelay: Int32
    /// The number of control packets supplied by packet filter.
    public let pktSndFilterExtraTotal: Int32
    /// The number of filter control packets received and consumed by the packet filter.
    public let pktRcvFilterExtraTotal: Int32
    /// The number of packets recovered by the packet filter, such as through forward error correction.
    public let pktRcvFilterSupplyTotal: Int32
    /// The number of lost packets that the packet filter could not recover.
    public let pktRcvFilterLossTotal: Int32
    /// The number of control packets supplied by packet filter.
    public let pktSndFilterExtra: Int32
    /// The number of filter control packets received and consumed by the packet filter.
    public let pktRcvFilterExtra: Int32
    /// The number of packets recovered by the packet filter, such as through forward error correction.
    public let pktRcvFilterSupply: Int32
    /// The number of lost packets that the packet filter could not recover.
    public let pktRcvFilterLoss: Int32
    /// The packet reordering tolerance, measured in packets.
    public let pktReorderTolerance: Int32

    init(mon: CBytePerfMon) {
        self.msTimeStamp = mon.msTimeStamp
        self.pktSentTotal = mon.pktSentTotal
        self.pktRecvTotal = mon.pktRecvTotal
        self.pktSndLossTotal = mon.pktSndLossTotal
        self.pktRcvLossTotal = mon.pktRcvLossTotal
        self.pktRetransTotal = mon.pktRetransTotal
        self.pktSentACKTotal = mon.pktSentACKTotal
        self.pktRecvACKTotal = mon.pktRecvACKTotal
        self.pktSentNAKTotal = mon.pktSentNAKTotal
        self.pktRecvNAKTotal = mon.pktRecvNAKTotal
        self.usSndDurationTotal = mon.usSndDurationTotal
        self.pktSndDropTotal = mon.pktSndDropTotal
        self.pktRcvDropTotal = mon.pktRcvDropTotal
        self.pktRcvUndecryptTotal = mon.pktRcvUndecryptTotal
        self.byteSentTotal = mon.byteSentTotal
        self.byteRecvTotal = mon.byteRecvTotal
        self.byteRcvLossTotal = mon.byteRcvLossTotal
        self.byteRetransTotal = mon.byteRetransTotal
        self.byteSndDropTotal = mon.byteSndDropTotal
        self.byteRcvDropTotal = mon.byteRcvDropTotal
        self.byteRcvUndecryptTotal = mon.byteRcvUndecryptTotal
        self.pktSent = mon.pktSent
        self.pktRecv = mon.pktRecv
        self.pktSndLoss = mon.pktSndLoss
        self.pktRcvLoss = mon.pktRcvLoss
        self.pktRetrans = mon.pktRetrans
        self.pktRcvRetrans = mon.pktRcvRetrans
        self.pktSentACK = mon.pktSentACK
        self.pktRecvACK = mon.pktRecvACK
        self.pktSentNAK = mon.pktSentNAK
        self.pktRecvNAK = mon.pktRecvNAK
        self.mbpsSendRate = mon.mbpsSendRate
        self.mbpsRecvRate = mon.mbpsRecvRate
        self.usSndDuration = mon.usSndDuration
        self.pktReorderDistance = mon.pktReorderDistance
        self.pktRcvAvgBelatedTime = mon.pktRcvAvgBelatedTime
        self.pktRcvBelated = mon.pktRcvBelated
        self.pktSndDrop = mon.pktSndDrop
        self.pktRcvDrop = mon.pktRcvDrop
        self.pktRcvUndecrypt = mon.pktRcvUndecrypt
        self.byteSent = mon.byteSent
        self.byteRecv = mon.byteRecv
        self.byteRcvLoss = mon.byteRcvLoss
        self.byteRetrans = mon.byteRetrans
        self.byteSndDrop = mon.byteSndDrop
        self.byteRcvDrop = mon.byteRcvDrop
        self.byteRcvUndecrypt = mon.byteRcvUndecrypt
        self.usPktSndPeriod = mon.usPktSndPeriod
        self.pktFlowWindow = mon.pktFlowWindow
        self.pktCongestionWindow = mon.pktCongestionWindow
        self.pktFlightSize = mon.pktFlightSize
        self.msRTT = mon.msRTT
        self.mbpsBandwidth = mon.mbpsBandwidth
        self.byteAvailSndBuf = mon.byteAvailSndBuf
        self.byteAvailRcvBuf = mon.byteAvailRcvBuf
        self.mbpsMaxBW = mon.mbpsMaxBW
        self.byteMSS = mon.byteMSS
        self.pktSndBuf = mon.pktSndBuf
        self.byteSndBuf = mon.byteSndBuf
        self.msSndBuf = mon.msSndBuf
        self.msSndTsbPdDelay = mon.msSndTsbPdDelay
        self.pktRcvBuf = mon.pktRcvBuf
        self.byteRcvBuf = mon.byteRcvBuf
        self.msRcvBuf = mon.msRcvBuf
        self.msRcvTsbPdDelay = mon.msRcvTsbPdDelay
        self.pktSndFilterExtraTotal = mon.pktSndFilterExtraTotal
        self.pktRcvFilterExtraTotal = mon.pktRcvFilterExtraTotal
        self.pktRcvFilterSupplyTotal = mon.pktRcvFilterSupplyTotal
        self.pktRcvFilterLossTotal = mon.pktRcvFilterLossTotal
        self.pktSndFilterExtra = mon.pktSndFilterExtra
        self.pktRcvFilterExtra = mon.pktRcvFilterExtra
        self.pktRcvFilterSupply = mon.pktRcvFilterSupply
        self.pktRcvFilterLoss = mon.pktRcvFilterLoss
        self.pktReorderTolerance = mon.pktReorderTolerance
    }
}
