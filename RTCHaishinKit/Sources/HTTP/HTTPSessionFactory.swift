import Foundation
import HaishinKit

/// Creates WebRTC sessions with HTTP signaling for WHIP publishing or WHEP playback.
///
/// Register this factory with `StreamSessionBuilderFactory` before building sessions for its URL schemes.
public struct HTTPSessionFactory: StreamSessionFactory {
    /// The endpoint URL schemes supported by this factory.
    public let supportedProtocols: Set<String> = ["http", "https"]

    /// Creates a session factory.
    public init() {
    }

    /// Creates a session without connecting it.
    ///
    /// Pass `HTTPSessionConfiguration` to configure the peer connection. Other configuration types are ignored.
    ///
    /// - Parameters:
    ///   - uri: The endpoint URL.
    ///   - mode: Whether to publish or play media.
    ///   - configuration: Optional protocol-specific settings.
    /// - Returns: A session configured for the endpoint and mode.
    public func make(_ uri: URL, mode: StreamSessionMode, configuration: (any StreamSessionConfiguration)?) -> any StreamSession {
        return HTTPSession(uri: uri, mode: mode, configuration: configuration)
    }
}
