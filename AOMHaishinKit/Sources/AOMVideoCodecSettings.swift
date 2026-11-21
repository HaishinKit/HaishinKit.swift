import CoreMedia
import Foundation

/// Settings for standalone, 8-bit software AV1 compression.
///
/// Validation occurs when creating or updating a ``AOMVideoEncoder``.
public struct AOMVideoCodecSettings: Codable, Sendable, Equatable {
    /// The libaom rate-control strategy. Neither mode guarantees an exact bitrate.
    public enum BitRateMode: String, Codable, Sendable {
        /// Variable rate targeting the configured average bitrate.
        case average
        /// Constant-rate control targeting the configured bitrate.
        case constant
    }

    /// Required input and output size in pixels; the caller must resize input beforehand. Both dimensions must be positive, even integers.
    ///
    /// The total may not exceed 16,777,216 pixels. Each dimension must also fit
    /// the AV1 limit of 65,535.
    public var videoSize: CGSize
    /// Target bits per second. Must be positive; libaom uses whole kilobits per second.
    public var bitRate: Int
    /// Frame-rate hint and fallback for missing frame durations, in frames per second.
    /// Must be finite and between 0.001 and 1,000,000 inclusive.
    public var expectedFrameRate: Double
    /// Maximum interval between requested keyframes, in seconds of presentation time.
    /// Must be finite and between 0.000001 and 3,600 inclusive.
    public var maxKeyFrameIntervalDuration: Double
    /// Rate-control strategy. Changing this requires a new encoder.
    public var bitRateMode: BitRateMode

    /// Creates a configuration. Values are validated by the encoder, not this initializer.
    /// - Parameters:
    ///   - videoSize: Output width and height in pixels; defaults to 640 × 480.
    ///   - bitRate: Target bits per second; defaults to 1,000,000.
    ///   - expectedFrameRate: Frame-rate hint; defaults to 30 frames per second.
    ///   - maxKeyFrameIntervalDuration: Maximum keyframe interval; defaults to 2 seconds.
    ///   - bitRateMode: Rate control; defaults to average bitrate.
    public init(videoSize: CGSize = CGSize(width: 640, height: 480), bitRate: Int = 1_000_000,
                expectedFrameRate: Double = 30, maxKeyFrameIntervalDuration: Double = 2,
                bitRateMode: BitRateMode = .average) {
        self.videoSize = videoSize
        self.bitRate = bitRate
        self.expectedFrameRate = expectedFrameRate
        self.maxKeyFrameIntervalDuration = maxKeyFrameIntervalDuration
        self.bitRateMode = bitRateMode
    }
}
