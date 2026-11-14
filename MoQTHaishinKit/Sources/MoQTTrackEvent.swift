import Foundation

/// A track discovered through a prefix subscription.
public enum MoQTTrackEvent: Sendable {
    /// A peer publication accepted for the prefix subscription.
    case published(MoQTPublishedTrack)
    /// A track the peer skipped, identified by the namespace suffix and track name.
    case skipped(namespaceSuffix: [Data], name: Data)
}
