import HaishinKit
import libdatachannel

extension VideoCodecSettings.Format {
    var cValue: rtcCodec {
        switch self {
        case .h264:
            return RTC_CODEC_H264
        case .hevc:
            return RTC_CODEC_H265
        case .vp8:
            return RTC_CODEC_VP8
        case .vp9:
            return RTC_CODEC_VP9
        }
    }
}
