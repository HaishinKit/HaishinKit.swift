import Foundation

/// A type that represents a streaming session factory.
public protocol StreamSessionFactory {
    /// The supported protocols.
    var supportedProtocols: Set<String> { get }

    /// Makes a new session by uri.
    func make(_ uri: URL, mode: StreamSessionMode, configuration: (any StreamSessionConfiguration)?) -> any StreamSession
}
