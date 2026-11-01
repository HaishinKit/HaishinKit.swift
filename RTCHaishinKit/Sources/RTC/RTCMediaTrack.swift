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
    public func setStream(_ stream: RTCStream) async {
        await stream.addTrack(self)
    }

    private let track: RTCTrack

    init(_ tid: Int32, id: String) throws {
        track = try RTCTrack(id: tid)
        self.id = id
    }

    func send(_ buffer: CMSampleBuffer) {
        track.send(buffer)
    }

    func send(_ buffer: AVAudioCompressedBuffer, when: AVAudioTime) {
        track.send(buffer, when: when)
    }

    func setDelegate(_ delegate: some RTCTrackDelegate) {
        track.delegate = delegate
    }
}
