/// The intended application role for a MOQT connection. The role is local metadata.
public enum MoQTSetupRole: Int, Sendable {
    /// An endpoint that publishes tracks.
    case publisher = 1
    /// An endpoint that subscribes to tracks.
    case subscriber = 2
    /// An endpoint that publishes and subscribes to tracks.
    case pubSub = 3
}
