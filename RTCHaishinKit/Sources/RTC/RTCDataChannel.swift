import Foundation
import libdatachannel

/// A delegate that receives data channel messages and state changes.
public protocol RTCDataChannelDelegate: AnyObject {
    /// Called when the data channel’s state changes.
    /// - Parameters:
    ///   - dataChannel: The RTCDataChannel instance.
    ///   - readyState: The updated channel state.
    func dataChannel(_ dataChannel: RTCDataChannel, readyStateChanged readyState: RTCDataChannel.ReadyState)

    /// Called when a binary message is received.
    /// - Parameters:
    ///   - dataChannel: The RTCDataChannel instance.
    ///   - message: The received binary data.
    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessage message: Data)

    /// Called when a text message is received.
    /// - Parameters:
    ///   - dataChannel: The RTCDataChannel instance.
    ///   - message: The received text message.
    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessage message: String)
}

/// A WebRTC data channel for exchanging messages with a peer.
///
/// Create a channel with `RTCPeerConnection.createDataChannel(_:)`, or receive one
/// through the peer connection delegate.
public final class RTCDataChannel: RTCChannel {
    /// Represents the ready state of an RTCDataChannel.
    public enum ReadyState {
        /// The data channel is being created and the connection is in progress.
        case connecting
        /// The data channel is fully established and ready to send and receive messages.
        case open
        /// The data channel is in the process of closing.
        case closing
        /// The data channel has been closed and can no longer be used.
        case closed
    }

    /// The delegate that receives messages and channel state changes.
    public weak var delegate: (any RTCDataChannelDelegate)?

    /// The channel’s label, or an empty string if the library cannot retrieve it.
    public var label: String {
        do {
            return try CUtil.getString { buffer, size in
                rtcGetDataChannelLabel(id, buffer, size)
            }
        } catch {
            logger.warn(error)
            return ""
        }
    }

    /// The SCTP stream identifier returned by the underlying library.
    public var stream: Int {
        Int(rtcGetDataChannelStream(id))
    }

    /// The channel state reported by its callbacks.
    public private(set) var readyState: ReadyState = .connecting {
        didSet {
            delegate?.dataChannel(self, readyStateChanged: readyState)
        }
    }

    let id: Int32

    init(id: Int32) throws {
        self.id = id
        try RTCError.check(id)
        do {
            try RTCError.check(rtcSetOpenCallback(id) { _, pointer in
                guard let pointer else { return }
                Unmanaged<RTCDataChannel>.fromOpaque(pointer).takeUnretainedValue().readyState = .open
            })
            try RTCError.check(rtcSetClosedCallback(id) { _, pointer in
                guard let pointer else { return }
                Unmanaged<RTCDataChannel>.fromOpaque(pointer).takeUnretainedValue().readyState = .closed
            })
            try RTCError.check(rtcSetMessageCallback(id) { _, bytes, size, pointer in
                guard let bytes, let pointer else { return }
                if 0 <= size {
                    let data = Data(bytes: bytes, count: Int(size))
                    Unmanaged<RTCDataChannel>.fromOpaque(pointer).takeUnretainedValue().didReceiveMessage(data)
                } else {
                    Unmanaged<RTCDataChannel>.fromOpaque(pointer).takeUnretainedValue().didReceiveMessage(String(cString: bytes))
                }
            })
            try RTCError.check(rtcSetErrorCallback(id) { _, error, pointer in
                guard let error, let pointer else { return }
                Unmanaged<RTCDataChannel>.fromOpaque(pointer).takeUnretainedValue().errorOccurred(String(cString: error))
            })
            rtcSetUserPointer(id, Unmanaged.passUnretained(self).toOpaque())
        } catch {
            rtcDeleteDataChannel(id)
            throw error
        }
    }

    deinit {
        rtcDeleteDataChannel(id)
    }

    /// Sends a text message over the data channel.
    ///
    /// - Parameter message: The text to send.
    /// - Throws: `RTCError` if the library rejects the send operation.
    public func send(_ message: String) throws {
        try RTCError.check(message.withCString { pointer in
            rtcSendMessage(id, pointer, -1)
        })
    }

    private func errorOccurred(_ error: String) {
        logger.warn(error)
    }

    private func didReceiveMessage(_ message: Data) {
        delegate?.dataChannel(self, didReceiveMessage: message)
    }

    private func didReceiveMessage(_ message: String) {
        delegate?.dataChannel(self, didReceiveMessage: message)
    }
}
