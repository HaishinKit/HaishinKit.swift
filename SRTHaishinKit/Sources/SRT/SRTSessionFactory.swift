import Foundation
import HaishinKit

/// Creates SRT publishing and playback sessions.
///
/// Register this factory with `StreamSessionBuilderFactory` before building sessions for its URL schemes.
public struct SRTSessionFactory: StreamSessionFactory {
    /// The endpoint URL schemes supported by this factory.
    public let supportedProtocols: Set<String> = ["srt"]

    /// Creates a session factory.
    public init() {
    }

    /// Creates a session without connecting it.
    ///
    /// This factory ignores `configuration`; supply SRT socket options in the endpoint URL.
    ///
    /// - Parameters:
    ///   - uri: The endpoint URL.
    ///   - mode: Whether to publish or play media.
    ///   - configuration: Optional protocol-specific settings.
    /// - Returns: A session configured for the endpoint and mode.
    public func make(_ uri: URL, mode: StreamSessionMode, configuration: (any StreamSessionConfiguration)?) -> any StreamSession {
        return SRTSession(uri: uri, mode: mode, configuration: configuration)
    }
}
