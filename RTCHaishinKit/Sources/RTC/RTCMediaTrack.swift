import AVFoundation
import HaishinKit
import libdatachannel

/// A media track that can be associated with a stream.
public actor RTCMediaTrack: RTCStreamTrack {
    /// The identifier of this track.
    public let id: String

    /// The media identifier used in SDP.
    public var mid: String { track.mid }

    /// Associates the track with a stream for media delivery and transmission.
    /// Repeating the association has no effect. Associating another stream moves the track.
    public func setStream(_ stream: RTCStream) async {
        await updateStream(stream, detachingFrom: nil)
    }

    private let track: RTCTrack
    private weak var stream: RTCStream?
    private var streamUpdate: Task<Void, Never>?

    init(_ tid: Int32, id: String) throws {
        track = try RTCTrack(id: tid)
        self.id = id
    }

    func send(_ buffer: CMSampleBuffer, from stream: RTCStream) {
        guard self.stream === stream else { return }
        track.send(buffer)
    }

    func send(_ buffer: AVAudioCompressedBuffer, when: AVAudioTime, from stream: RTCStream) {
        guard self.stream === stream else { return }
        track.send(buffer, when: when)
    }

    func detach(from stream: RTCStream) async {
        await updateStream(nil, detachingFrom: stream)
    }

    private func updateStream(_ destination: RTCStream?, detachingFrom source: RTCStream?) async {
        // Serialize updates across the awaits on the old and new stream actors.
        let previousUpdate = streamUpdate
        let update = Task {
            await previousUpdate?.value
            if let source, stream !== source { return }
            guard stream !== destination else { return }
            let previousStream = stream
            stream = nil
            track.delegate = nil
            await previousStream?.removeTrack(self)
            stream = destination
            track.delegate = destination
            await destination?.addTrack(self)
        }
        streamUpdate = update
        await update.value
    }
}
