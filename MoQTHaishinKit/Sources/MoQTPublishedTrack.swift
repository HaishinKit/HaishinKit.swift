import Foundation

/// A track offered by a publisher on the session.
public struct MoQTPublishedTrack: Sendable {
    /// The namespace fields of the track.
    public let namespace: [Data]
    /// The track name bytes.
    public let name: Data
    /// The alias used to identify incoming objects for the track.
    public let trackAlias: UInt64
    /// The track properties advertised by the publisher.
    public let properties: [MoQTKeyValue]
}
