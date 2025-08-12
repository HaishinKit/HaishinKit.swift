import CoreMedia
import Foundation

extension CMFormatDescription {
    var streamType: ESStreamType {
        switch mediaSubType {
        case .hevc:
            return .h265
        case .h264:
            return .h264
        case .mpeg4AAC_LD:
            return .adtsAac
        case .mpeg4AAC:
            return .adtsAac
        default:
            return .unspecific
        }
    }
}
