import HaishinKit

enum RTMPAudioFourCC: UInt32, CustomStringConvertible {
    case ac3 = 0x61632D33 // ac-3
    case eac3 = 0x65632D33  // ec-3
    case opus = 0x4F707573 // Opus
    case mp3 = 0x2E6D7033 // .mp3
    case flac = 0x664C6143 // fLaC
    case aac = 0x6D703461 // mp4a

    var description: String {
        switch self {
        case .ac3:
            return "ac-3"
        case .eac3:
            return "ex-3"
        case .opus:
            return "Opus"
        case .mp3:
            return ".mp3"
        case .flac:
            return "fLaC"
        case .aac:
            return "mp4a"
        }
    }

    var isSupported: Bool {
        switch self {
        case .ac3:
            return false
        case .eac3:
            return false
        case .opus:
            return true
        case .mp3:
            return false
        case .flac:
            return false
        case .aac:
            return false
        }
    }
}

enum RTMPAudioPacketType: UInt8 {
    case sequenceStart = 0
    case codedFrames = 1
    case sequenceEnd = 2
    case multiChannelConfig = 4
    case multiTrack = 5
    case modEx = 7
}

enum RTMPAudioPacketModExType: Int {
    case timestampOffsetNano = 0
}

enum RTMPAVMultiTrackType: Int {
    case oneTrack = 0
    case manyTracks = 1
    case manyTracksManyCOdecs = 2
}

enum RTMPAudioChannelOrder: Int {
    case unspecified = 0
    case native = 1
    case custom = 2
}

enum RTMPVideoFourCC: UInt32, CustomStringConvertible {
    case av1 = 0x61763031 // av01
    case vp9 = 0x76703039 // vp09
    case hevc = 0x68766331 // hvc1

    var description: String {
        switch self {
        case .av1:
            return "av01"
        case .vp9:
            return "vp09"
        case .hevc:
            return "hvc1"
        }
    }

    var isSupported: Bool {
        switch self {
        case .av1:
            return false
        case .vp9:
            return false
        case .hevc:
            return true
        }
    }
}

enum RTMPVideoPacketType: UInt8 {
    case sequenceStart = 0
    case codedFrames = 1
    case sequenceEnd = 2
    case codedFramesX = 3
    case metadata = 4
    case mpeg2TSSequenceStart = 5
}

extension AudioCodecSettings.Format {
    var codecid: Int {
        switch self {
        case .aac:
            return Int(RTMPAudioCodec.aac.rawValue)
        case .opus:
            return Int(RTMPAudioFourCC.opus.rawValue)
        case .pcm:
            return Int(RTMPAudioCodec.pcm.rawValue)
        }
    }
}

extension VideoCodecSettings.Format {
    var codecid: Int {
        switch self {
        case .h264:
            return Int(RTMPVideoCodec.avc.rawValue)
        case .hevc:
            return Int(RTMPVideoFourCC.hevc.rawValue)
        }
    }
}
