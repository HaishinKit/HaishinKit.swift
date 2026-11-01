import Foundation
import Network

/// The RTMPTransportStatistics represents the TCP statistics of the RTMPConnection. This struct is a wrapper for an NWConnection.DataTransferReport.PathReport.
/// - seealso: https://developer.apple.com/documentation/network/nwconnection/datatransferreport/pathreport
public struct RTMPTransportStatistics: Sendable {
    /// The smoothed round-trip time, in seconds.
    public let transportSmoothedRTT: TimeInterval
    /// The minimum round-trip time since the connection was established, in seconds.
    public let transportMinimumRTT: TimeInterval
    /// The round-trip time variance, in seconds.
    public let transportRTTVariance: TimeInterval

    init(report: NWConnection.DataTransferReport.PathReport) {
        self.transportSmoothedRTT = report.transportSmoothedRTT
        self.transportMinimumRTT = report.transportMinimumRTT
        self.transportRTTVariance = report.transportRTTVariance
    }
}
