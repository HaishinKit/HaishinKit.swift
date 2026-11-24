import CoreImage
import CoreMedia

extension CMVideoFormatDescription {
    var configurationBox: Data? {
        guard let atoms = CMFormatDescriptionGetExtension(self, extensionKey: kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms) as? NSDictionary else {
            return nil
        }
        switch mediaSubType {
        case .h264:
            return atoms["avcC"] as? Data
        case .hevc:
            return atoms["hvcC"] as? Data
        case let type where type.rawValue == kCMVideoCodecType_AV1:
            return atoms["av1C"] as? Data
        default:
            return nil
        }
    }

    func makeDecodeConfigurtionRecord() -> (any DecoderConfigurationRecord)? {
        guard let configurationBox else {
            return nil
        }
        switch mediaSubType {
        case .h264:
            return AVCDecoderConfigurationRecord(data: configurationBox)
        case .hevc:
            return HEVCDecoderConfigurationRecord(data: configurationBox)
        default:
            return nil
        }
    }
}
