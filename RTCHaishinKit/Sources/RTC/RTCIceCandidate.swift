import Foundation

/// An ICE candidate exchanged through signaling.
public struct RTCIceCandidate: Sendable {
    public let candidate: String
    public let mid: String

    /// Creates a candidate received through signaling.
    public init(candidate: String, mid: String) {
        self.candidate = candidate
        self.mid = mid
    }
}

extension RTCIceCandidate {
    init(candidate: UnsafePointer<CChar>?, mid: UnsafePointer<CChar>?) {
        if let candidate {
            self.candidate = String(cString: candidate)
        } else {
            self.candidate = ""
        }
        if let mid {
            self.mid = String(cString: mid)
        } else {
            self.mid = ""
        }
    }
}
