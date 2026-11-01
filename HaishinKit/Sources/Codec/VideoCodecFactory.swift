import CoreMedia
import Foundation

/// Registers optional codec implementations before starting media streams.
/// H.264 and HEVC are available through VideoToolbox without registration.
public actor VideoCodecFactory {
    public static let shared = VideoCodecFactory()

    public enum Error: Swift.Error {
        /// No registered implementation supports this codec and direction.
        case unsupportedCodec(UInt32)
    }

    // Session creation remains synchronous: no actor hop is needed per frame.
    private nonisolated let registry = Registry()

    /// Creates an independent registry, including the standard codecs.
    public init() {
    }

    /// Registers a provider once per concrete factory type.
    public func register(_ factory: some VideoCodecSessionFactory) {
        registry.register(factory)
    }

    /// Lists the formats currently available in this direction.
    public func supportedFormats(for mode: VideoCodecSessionMode) -> [VideoCodecSettings.Format] {
        var formats: [VideoCodecSettings.Format] = []
        for factory in registry.snapshot() {
            for format in factory.supportedFormats(for: mode) where !formats.contains(format) {
                formats.append(format)
            }
        }
        return formats
    }

    /// Creates a session from a thread-safe snapshot of the registered providers.
    /// Register providers before creating sessions. Existing sessions are unchanged.
    public nonisolated func makeSession(mode: VideoCodecSessionMode, settings: VideoCodecSettings, inputFormat: CMFormatDescription) throws -> any VideoCodecSession {
        let codecType = mode == .compression ? settings.format.codecType : CMFormatDescriptionGetMediaSubType(inputFormat)
        for factory in registry.snapshot() where factory.supportedFormats(for: mode).contains(where: { $0.codecType == codecType }) {
            return try factory.makeSession(mode: mode, settings: settings, inputFormat: inputFormat)
        }
        throw Error.unsupportedCodec(codecType)
    }

    private final class Registry: @unchecked Sendable {
        private let lock = NSLock()
        private var factories: [any VideoCodecSessionFactory] = [VTVideoCodecSessionFactory()]

        func register(_ factory: some VideoCodecSessionFactory) {
            lock.lock()
            defer { lock.unlock() }
            guard !factories.contains(where: { ObjectIdentifier(type(of: $0)) == ObjectIdentifier(type(of: factory)) }) else {
                return
            }
            factories.append(factory)
        }

        func snapshot() -> [any VideoCodecSessionFactory] {
            lock.lock()
            defer { lock.unlock() }
            return factories
        }
    }
}
