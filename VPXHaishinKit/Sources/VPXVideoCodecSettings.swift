import CoreMedia
import Foundation

/// Settings for standalone, 8-bit software VP8/VP9 compression.
public struct VPXVideoCodecSettings: Codable, Sendable, Equatable {
    public enum Format: String, CaseIterable, Codable, Sendable {
        case vp8, vp9
        public var codecType: CMVideoCodecType { self == .vp8 ? 0x76703038 : kCMVideoCodecType_VP9 }
        var identifier: Int32 { self == .vp8 ? 8 : 9 }
    }
    public enum BitRateMode: String, Codable, Sendable { case average, constant }
    public enum ScalingMode: String, Codable, Sendable {
        case normal = "Normal", letterbox = "Letterbox", trim = "Trim"
    }
    public var videoSize: CGSize
    public var bitRate: Int
    public var expectedFrameRate: Double
    public var maxKeyFrameIntervalDuration: Double
    public var format: Format
    public var bitRateMode: BitRateMode
    public var scalingMode: ScalingMode

    public init(videoSize: CGSize = CGSize(width: 640, height: 480), bitRate: Int = 1_000_000,
                expectedFrameRate: Double = 30, maxKeyFrameIntervalDuration: Double = 2,
                format: Format = .vp9, bitRateMode: BitRateMode = .average, scalingMode: ScalingMode = .normal) {
        self.videoSize = videoSize; self.bitRate = bitRate; self.expectedFrameRate = expectedFrameRate
        self.maxKeyFrameIntervalDuration = maxKeyFrameIntervalDuration; self.format = format
        self.bitRateMode = bitRateMode; self.scalingMode = scalingMode
    }
}

/// Errors thrown directly to the caller; unsupported configurations never select another codec.
public enum VPXVideoCodecError: Swift.Error {
    case invalidSettings, unsupportedFormat, invalidTimestamp, invalidSession
    case codec(Int32)
    case coreMedia(OSStatus)
}
