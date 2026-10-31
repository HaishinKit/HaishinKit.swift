import Foundation

/// A local ICE candidate delivered by the peer connection delegate.
public struct RTCIceCandidate: Sendable {
    let candidate: String
    let mid: String
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
