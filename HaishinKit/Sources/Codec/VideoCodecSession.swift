import CoreMedia

/// Whether a codec session compresses or decompresses video.
public enum VideoCodecSessionMode: Sendable, Equatable {
    case compression
    case decompression
}

/// A video converter confined to its owning stream. Calls must be serialized.
public protocol VideoCodecSession: AnyObject {
    /// Converts a frame and delivers its output through the continuation.
    func convert(_ sampleBuffer: CMSampleBuffer, continuation: AsyncStream<CMSampleBuffer>.Continuation?) throws
    /// Applies settings that can change without recreating the session.
    func update(_ settings: VideoCodecSettings) throws
    /// Releases resources. Repeated calls must be safe.
    func invalidate()
}

/// Creates video converters for an optional codec implementation.
public protocol VideoCodecSessionFactory: Sendable {
    /// The formats implemented in the requested direction.
    func supportedFormats(for mode: VideoCodecSessionMode) -> [VideoCodecSettings.Format]
    /// Creates a converter. For decompression, the input format selects the codec.
    func makeSession(mode: VideoCodecSessionMode, settings: VideoCodecSettings, inputFormat: CMFormatDescription) throws -> any VideoCodecSession
}
