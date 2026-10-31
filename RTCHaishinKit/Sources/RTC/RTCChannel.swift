import Foundation
import HaishinKit
import libdatachannel

protocol RTCChannel {
    var id: Int32 { get }

    func send(_ message: Data) throws
}

extension RTCChannel {
    /// Sends a binary message over the channel.
    ///
    /// - Parameter message: The bytes to send.
    /// - Throws: `RTCError` if the library rejects the send operation.
    public func send(_ message: Data) throws {
        try RTCError.check(message.withUnsafeBytes { pointer in
            return rtcSendMessage(id, pointer.bindMemory(to: CChar.self).baseAddress, Int32(message.count))
        })
    }
}
