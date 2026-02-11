import Foundation

/// An actor that provides builder for Session object.
public actor StreamSessionBuilder {
    private let factory: StreamSessionBuilderFactory
    private let uri: URL
    private var mode: StreamSessionMode = .publish
    private var configuration: (any StreamSessionConfiguration)?

    init(factory: StreamSessionBuilderFactory, uri: URL) {
        self.factory = factory
        self.uri = uri
    }

    /// Sets a method.
    public func setMode(_ mode: StreamSessionMode) -> Self {
        self.mode = mode
        return self
    }

    /// Sets a config.
    public func setConfiguration(_ configuration: (any StreamSessionConfiguration)?) -> Self {
        self.configuration = configuration
        return self
    }

    /// Creates a Session instance with the specified fields.
    public func build() async throws -> (any StreamSession)? {
        return try await factory.build(uri, method: mode, configuration: configuration)
    }
}
