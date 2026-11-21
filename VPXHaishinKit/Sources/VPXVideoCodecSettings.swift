import CoreMedia
import Foundation

/// Settings for standalone, 8-bit software VP8/VP9 compression.
///
/// Validation occurs when creating or updating a ``VPXVideoEncoder``.
public struct VPXVideoCodecSettings: Codable, Sendable, Equatable {
    /// The compressed bitstream format.
    public enum Format: String, CaseIterable, Codable, Sendable {
        /// VP8 with 8-bit YUV 4:2:0 output.
        case vp8
        /// VP9 profile 0 with 8-bit YUV 4:2:0 output.
        case vp9

        /// The Core Media subtype used in compressed sample descriptions.
        public var codecType: CMVideoCodecType { self == .vp8 ? 0x76703038 : kCMVideoCodecType_VP9 }
        var identifier: Int32 { self == .vp8 ? 8 : 9 }
    }

    /// The libvpx rate-control strategy. Neither mode guarantees an exact bitrate.
    public enum BitRateMode: String, Codable, Sendable {
        /// Variable rate targeting the configured average bitrate.
        case average
        /// Constant-rate control targeting the configured bitrate.
        case constant
    }

    /// How VideoToolbox fits an input image to the output dimensions.
    public enum ScalingMode: String, Codable, Sendable {
        /// Scales to fill the dimensions, allowing aspect-ratio changes.
        case normal = "Normal"
        /// Preserves aspect ratio and adds borders to fit the complete image.
        case letterbox = "Letterbox"
        /// Preserves aspect ratio and crops the image to fill the dimensions.
        case trim = "Trim"
    }

    /// Output size in pixels. Both dimensions must be positive, even integers.
    ///
    /// The total may not exceed 16,777,216 pixels. Each dimension must also fit
    /// the codec limit: 16,383 for VP8 or 65,535 for VP9.
    public var videoSize: CGSize
    /// Target bits per second. Must be positive; libvpx uses whole kilobits per second.
    public var bitRate: Int
    /// Frame-rate hint and fallback for missing frame durations, in frames per second.
    /// Must be finite and between 0.001 and 1,000,000 inclusive.
    public var expectedFrameRate: Double
    /// Maximum interval between requested keyframes, in seconds of presentation time.
    /// Must be finite and between 0.000001 and 3,600 inclusive.
    public var maxKeyFrameIntervalDuration: Double
    /// Output codec. Changing this requires a new encoder.
    public var format: Format
    /// Rate-control strategy. Changing this requires a new encoder.
    public var bitRateMode: BitRateMode
    /// Input scaling strategy. Changing this requires a new encoder.
    public var scalingMode: ScalingMode

    /// Creates a configuration. Values are validated by the encoder, not this initializer.
    /// - Parameters:
    ///   - videoSize: Output width and height in pixels; defaults to 640 × 480.
    ///   - bitRate: Target bits per second; defaults to 1,000,000.
    ///   - expectedFrameRate: Frame-rate hint; defaults to 30 frames per second.
    ///   - maxKeyFrameIntervalDuration: Maximum keyframe interval; defaults to 2 seconds.
    ///   - format: Output codec; defaults to VP9.
    ///   - bitRateMode: Rate control; defaults to average bitrate.
    ///   - scalingMode: Image fitting; defaults to normal scaling.
    public init(videoSize: CGSize = CGSize(width: 640, height: 480), bitRate: Int = 1_000_000,
                expectedFrameRate: Double = 30, maxKeyFrameIntervalDuration: Double = 2,
                format: Format = .vp9, bitRateMode: BitRateMode = .average, scalingMode: ScalingMode = .normal) {
        self.videoSize = videoSize
        self.bitRate = bitRate
        self.expectedFrameRate = expectedFrameRate
        self.maxKeyFrameIntervalDuration = maxKeyFrameIntervalDuration
        self.format = format
        self.bitRateMode = bitRateMode
        self.scalingMode = scalingMode
    }
}
