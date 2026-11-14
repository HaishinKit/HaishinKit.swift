import CoreMedia
import HaishinKit

/// Enables software VP8 and VP9 conversion after explicit registration.
///
/// ```swift
/// import HaishinKit
/// import VPXHaishinKit
/// await VideoCodecFactory.shared.register(VPXVideoCodecFactory())
/// ```
/// The provider supports 8-bit 4:2:0 video. Transport support is independent
/// of registration; this does not enable VP8/VP9 in RTC, RTMP, or SRT streams.
public struct VPXVideoCodecFactory: VideoCodecSessionFactory {
    public init() {
    }

    public func supportedFormats(for mode: VideoCodecSessionMode) -> [VideoCodecSettings.Format] {
        if mode == .compression {
            guard #available(iOS 16.0, tvOS 16.0, macCatalyst 16.0, *) else { return [] }
        }
        return [.vp8, .vp9]
    }

    public func makeSession(mode: VideoCodecSessionMode, settings: VideoCodecSettings, inputFormat: CMFormatDescription) throws -> any VideoCodecSession {
        guard CMFormatDescriptionGetMediaType(inputFormat) == kCMMediaType_Video else {
            throw VPXVideoCodecError.unsupportedFormat
        }
        let codecType = mode == .compression ? settings.format.codecType : CMFormatDescriptionGetMediaSubType(inputFormat)
        let codec: Int32
        switch codecType {
        case VideoCodecSettings.Format.vp8.codecType: codec = 8
        case VideoCodecSettings.Format.vp9.codecType: codec = 9
        default: throw VPXVideoCodecError.unsupportedFormat
        }
        switch mode {
        case .compression:
            if #available(iOS 16.0, tvOS 16.0, macCatalyst 16.0, *) {
                return try VPXEncoder(codec: codec, settings: settings)
            }
            throw VPXVideoCodecError.unsupportedPlatform
        case .decompression:
            return try VPXDecoder(codec: codec)
        }
    }
}

/// Errors reported by the software VP8/VP9 provider.
public enum VPXVideoCodecError: Swift.Error {
    case unsupportedPlatform
    case invalidSettings
    case unsupportedFormat
    case invalidTimestamp
    case invalidSession
    case codec(Int32)
    case coreMedia(OSStatus)
}
