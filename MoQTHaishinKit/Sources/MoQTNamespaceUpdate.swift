import Foundation

/// A discovery event for a namespace relative to the requested prefix.
public enum MoQTNamespaceUpdate: Sendable {
    /// The peer advertised the associated namespace suffix as a sequence of byte fields.
    case available([Data])
    /// The peer withdrew the associated namespace suffix.
    case unavailable([Data])
}
