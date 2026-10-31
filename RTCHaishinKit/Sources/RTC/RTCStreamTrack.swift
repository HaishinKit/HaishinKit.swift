import AVFAudio
import CoreMedia
import Foundation
import HaishinKit
import libdatachannel

/// A media track descriptor that can be associated with a WebRTC stream.
public protocol RTCStreamTrack: Sendable {
    /// The track’s identifier.
    var id: String { get }
}

/// An audio track descriptor containing codec settings for peer connection setup.
public struct AudioStreamTrack: RTCStreamTrack, Sendable {
    /// The generated identifier of the track descriptor.
    public let id: String
    /// The audio codec settings used to describe the track.
    public let settings: AudioCodecSettings

    /// Creates an audio track descriptor with a generated identifier.
    ///
    /// - Parameter settings: The audio codec settings for the track.
    public init(_ settings: AudioCodecSettings) {
        self.id = UUID().uuidString
        self.settings = settings
    }
}

/// A video track descriptor containing codec settings for peer connection setup.
public struct VideoStreamTrack: RTCStreamTrack, Sendable {
    /// The generated identifier of the track descriptor.
    public let id: String
    /// The video codec settings used to describe the track.
    public let settings: VideoCodecSettings

    /// Creates a video track descriptor with a generated identifier.
    ///
    /// - Parameter settings: The video codec settings for the track.
    public init(_ settings: VideoCodecSettings) {
        self.id = UUID().uuidString
        self.settings = settings
    }
}
