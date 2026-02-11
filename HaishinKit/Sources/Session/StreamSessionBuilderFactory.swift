import Foundation

/// An actor that provides a factory to create a SessionBuifer.
///
/// ## Prerequisites
/// You need to register the factory in advance as follows.
/// ```swift
/// import RTMPHaishinKit
/// import SRTHaishinKit
///
/// await StreamSessionBuilderFactory.shared.register(RTMPSessionFactory())
/// await StreamSessionBuilderFactory.shared.register(SRTSessionFactory())
/// ```
public actor StreamSessionBuilderFactory {
    /// The shared instance.
    public static let shared = StreamSessionBuilderFactory()

    /// The error domain codes.
    public enum Error: Swift.Error {
        /// An illegal argument.
        case illegalArgument
        /// The factory can't find a SessionBuilder.
        case notFound
    }

    private var factories: [any StreamSessionFactory] = []

    private init() {
    }

    /// Makes a new session builder.
    public func make(_ uri: URL?) throws -> StreamSessionBuilder {
        guard let uri else {
            throw Error.illegalArgument
        }
        return StreamSessionBuilder(factory: self, uri: uri)
    }

    /// Registers a factory.
    public func register(_ factory: some StreamSessionFactory) {
        guard !factories.contains(where: { $0.supportedProtocols == factory.supportedProtocols }) else {
            return
        }
        factories.append(factory)
    }

    func build(_ uri: URL?, method: StreamSessionMode, configuration: (any StreamSessionConfiguration)?) throws -> (any StreamSession) {
        guard let uri else {
            throw Error.illegalArgument
        }
        for factory in factories where factory.supportedProtocols.contains(uri.scheme ?? "") {
            return factory.make(uri, mode: method, configuration: configuration)
        }
        throw Error.notFound
    }
}
