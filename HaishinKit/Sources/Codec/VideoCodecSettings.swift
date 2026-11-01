import Foundation
import VideoToolbox

/// Constraints on the video codec compression settings.
public struct VideoCodecSettings: Codable, Sendable {
    /// The number of frame rate for 30fps.
    public static let frameInterval30 = (1 / 30) - 0.001
    /// The number of frame rate for 10fps.
    public static let frameInterval10 = (1 / 10) - 0.001
    /// The number of frame rate for 5fps.
    public static let frameInterval05 = (1 / 05) - 0.001
    /// The number of frame rate for 1fps.
    public static let frameInterval01 = (1 / 01) - 0.001

    /// The defulat value.
    public static let `default` = VideoCodecSettings()

    /// A bitRate mode that affectes how to encode the video source.
    public struct BitRateMode: Sendable, CustomStringConvertible, Codable, Hashable, Equatable {
        public static func == (lhs: VideoCodecSettings.BitRateMode, rhs: VideoCodecSettings.BitRateMode) -> Bool {
            lhs.key == rhs.key
        }

        /// The average bit rate.
        public static let average = BitRateMode(key: .averageBitRate)

        /// The constant bit rate.
        @available(iOS 16.0, tvOS 16.0, macOS 13.0, *)
        public static let constant = BitRateMode(key: .constantBitRate)

        /// The variable bit rate.
        /// - seealso: [kVTCompressionPropertyKey_VariableBitRate](https://developer.apple.com/documentation/videotoolbox/kvtcompressionpropertykey_variablebitrate)
        @available(iOS 26.0, tvOS 26.0, macOS 26.0, *)
        public static let variable = BitRateMode(key: .variableBitRate)

        let key: VTSessionOptionKey

        public var description: String {
            key.CFString as String
        }

        public func hash(into hasher: inout Hasher) {
            return hasher.combine(description)
        }
    }

    /**
     * The scaling mode.
     * - seealso: https://developer.apple.com/documentation/videotoolbox/kvtpixeltransferpropertykey_scalingmode
     * - seealso: https://developer.apple.com/documentation/videotoolbox/vtpixeltransfersession/pixel_transfer_properties/scaling_mode_constants
     */
    public enum ScalingMode: String, Codable, Sendable {
        /// kVTScalingMode_Normal
        case normal = "Normal"
        /// kVTScalingMode_Letterbox
        case letterbox = "Letterbox"
        /// kVTScalingMode_CropSourceToCleanAperture
        case cropSourceToCleanAperture = "CropSourceToCleanAperture"
        /// kVTScalingMode_Trim
        case trim = "Trim"
    }

    /// The type of the VideoCodec supports format.
    public enum Format: Codable, Sendable, CaseIterable, Hashable {
        case h264
        case hevc
        /// VP8 requires a registered codec provider.
        case vp8
        /// VP9 requires a registered codec provider.
        case vp9

        #if os(macOS)
        var encoderID: NSString {
            switch self {
            case .h264:
                #if arch(arm64)
                return NSString(string: "com.apple.videotoolbox.videoencoder.ave.avc")
                #else
                return NSString(string: "com.apple.videotoolbox.videoencoder.h264.gva")
                #endif
            case .hevc:
                return NSString(string: "com.apple.videotoolbox.videoencoder.ave.hevc")
            case .vp8, .vp9:
                return ""
            }
        }
        #endif

        public var codecType: UInt32 {
            switch self {
            case .h264:
                return kCMVideoCodecType_H264
            case .hevc:
                return kCMVideoCodecType_HEVC
            case .vp8:
                return 0x76703038 // vp08
            case .vp9:
                return kCMVideoCodecType_VP9
            }
        }
    }

    /// Specifies the video size of encoding video.
    public var videoSize: CGSize
    /// Specifies the bitrate.
    public var bitRate: Int
    /// The H.264 or HEVC profile level. Software VP8/VP9 providers ignore this value.
    public var profileLevel: String {
        didSet {
            guard format == .h264 || format == .hevc else {
                return
            }
            if profileLevel.contains("HEVC") {
                format = .hevc
            } else {
                format = .h264
            }
        }
    }
    /// Specifies the scalingMode.
    public var scalingMode: ScalingMode
    /// Specifies the bitRateMode.
    public var bitRateMode: BitRateMode
    /// Specifies the keyframeInterval.
    public var maxKeyFrameIntervalDuration: Int32
    /// Specifies the allowFrameRecording.
    public var allowFrameReordering: Bool? // swiftlint:disable:this discouraged_optional_boolean
    /// Specifies the dataRateLimits
    public var dataRateLimits: [Double]?
    /// Specifies the low-latency opretaion for an encoder.
    public var isLowLatencyRateControlEnabled: Bool
    /// Specifies the hardware accelerated encoder is enabled(TRUE), or not(FALSE) for macOS.
    public var isHardwareAcceleratedEnabled: Bool
    /// Specifies the video frame interval.
    public var frameInterval: Double = 0.0
    /// Specifies the expected frame rate for an encoder. It may optimize power consumption.
    public var expectedFrameRate: Double?

    /// The codec to use. Additional formats require a registered provider.
    public var format: Format = .h264 {
        didSet {
            guard format != oldValue else { return }
            if format == .hevc && !profileLevel.contains("HEVC") {
                profileLevel = kVTProfileLevel_HEVC_Main_AutoLevel as String
            } else if format == .h264 && profileLevel.contains("HEVC") {
                profileLevel = kVTProfileLevel_H264_Baseline_3_1 as String
            }
        }
    }

    /// Creates a new VideoCodecSettings instance.
    public init(
        videoSize: CGSize = .init(width: 854, height: 480),
        bitRate: Int = 640 * 1000,
        profileLevel: String = kVTProfileLevel_H264_Baseline_3_1 as String,
        scalingMode: ScalingMode = .trim,
        bitRateMode: BitRateMode = .average,
        maxKeyFrameIntervalDuration: Int32 = 2,
        // swiftlint:disable discouraged_optional_boolean
        allowFrameReordering: Bool? = nil,
        // swiftlint:enable discouraged_optional_boolean
        dataRateLimits: [Double]? = [0.0, 0.0],
        isLowLatencyRateControlEnabled: Bool = false,
        isHardwareAcceleratedEnabled: Bool = true,
        expectedFrameRate: Double? = nil,
        format: Format? = nil
    ) {
        self.videoSize = videoSize
        self.bitRate = bitRate
        self.profileLevel = profileLevel
        self.scalingMode = scalingMode
        self.bitRateMode = bitRateMode
        self.maxKeyFrameIntervalDuration = maxKeyFrameIntervalDuration
        self.allowFrameReordering = allowFrameReordering
        self.dataRateLimits = dataRateLimits
        self.isLowLatencyRateControlEnabled = isLowLatencyRateControlEnabled
        self.isHardwareAcceleratedEnabled = isHardwareAcceleratedEnabled
        self.expectedFrameRate = expectedFrameRate
        if profileLevel.contains("HEVC") {
            self.format = .hevc
        }
        if let format {
            self.format = format
            if format == .hevc && !profileLevel.contains("HEVC") {
                self.profileLevel = kVTProfileLevel_HEVC_Main_AutoLevel as String
            } else if format == .h264 && profileLevel.contains("HEVC") {
                self.profileLevel = kVTProfileLevel_H264_Baseline_3_1 as String
            }
        }
    }

    func invalidateSession(_ rhs: VideoCodecSettings) -> Bool {
        return !(format == rhs.format && videoSize == rhs.videoSize &&
                    maxKeyFrameIntervalDuration == rhs.maxKeyFrameIntervalDuration &&
                    scalingMode == rhs.scalingMode &&
                    allowFrameReordering == rhs.allowFrameReordering &&
                    bitRateMode == rhs.bitRateMode &&
                    profileLevel == rhs.profileLevel &&
                    dataRateLimits == rhs.dataRateLimits &&
                    isLowLatencyRateControlEnabled == rhs.isLowLatencyRateControlEnabled &&
                    isHardwareAcceleratedEnabled == rhs.isHardwareAcceleratedEnabled
        )
    }

    func apply(_ codec: VideoCodec, rhs: VideoCodecSettings) throws {
        try codec.session?.update(self)
        if frameInterval != rhs.frameInterval {
            codec.frameInterval = frameInterval
        }
    }

    // https://developer.apple.com/documentation/videotoolbox/encoding_video_for_live_streaming
    func makeOptions() -> Set<VTSessionOption> {
        let isBaseline = profileLevel.contains("Baseline")
        var options = Set<VTSessionOption>([
            .init(key: .realTime, value: kCFBooleanTrue),
            .init(key: .profileLevel, value: profileLevel as NSObject),
            .init(key: bitRateMode.key, value: NSNumber(value: bitRate)),
            .init(key: .maxKeyFrameIntervalDuration, value: NSNumber(value: maxKeyFrameIntervalDuration)),
            .init(key: .allowFrameReordering, value: (allowFrameReordering ?? !isBaseline) as NSObject),
            .init(key: .pixelTransferProperties, value: [
                "ScalingMode": scalingMode.rawValue
            ] as NSObject)
        ])
        if bitRateMode == .average {
            if let dataRateLimits, dataRateLimits.count == 2 {
                var limits = [Double](repeating: 0.0, count: 2)
                limits[0] = dataRateLimits[0] == 0 ? Double(bitRate) / 8 * 1.5 : dataRateLimits[0]
                limits[1] = dataRateLimits[1] == 0 ? Double(1.0) : dataRateLimits[1]
                options.insert(.init(key: .dataRateLimits, value: limits as NSArray))
            }
        }
        #if os(macOS)
        if isHardwareAcceleratedEnabled {
            options.insert(.init(key: .encoderID, value: format.encoderID))
            options.insert(.init(key: .enableHardwareAcceleratedVideoEncoder, value: kCFBooleanTrue))
            options.insert(.init(key: .requireHardwareAcceleratedVideoEncoder, value: kCFBooleanTrue))
        }
        #endif
        if !isBaseline && profileLevel.contains("H264") {
            options.insert(.init(key: .H264EntropyMode, value: kVTH264EntropyMode_CABAC))
        }
        return options
    }

    func makeEncoderSpecification() -> CFDictionary? {
        if isLowLatencyRateControlEnabled {
            return [kVTVideoEncoderSpecification_EnableLowLatencyRateControl: true as CFBoolean] as CFDictionary
        }
        return nil
    }
}
