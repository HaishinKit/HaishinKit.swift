import CoreImage
import CoreMedia

extension CMVideoFormatDescription {
    var isHDR: Bool {
        guard let transferFunction = CMFormatDescriptionGetExtension(self, extensionKey: kCMFormatDescriptionExtension_TransferFunction) as? String else {
            return false
        }
        return transferFunction == kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String ||
            transferFunction == kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String
    }

    package var isCompressed: Bool {
        switch CMFormatDescriptionGetMediaSubType(self) {
        case kCVPixelFormatType_1Monochrome,
             kCVPixelFormatType_2Indexed,
             kCVPixelFormatType_8Indexed,
             kCVPixelFormatType_1IndexedGray_WhiteIsZero,
             kCVPixelFormatType_2IndexedGray_WhiteIsZero,
             kCVPixelFormatType_4IndexedGray_WhiteIsZero,
             kCVPixelFormatType_8IndexedGray_WhiteIsZero,
             kCVPixelFormatType_16BE555,
             kCVPixelFormatType_16LE555,
             kCVPixelFormatType_16LE5551,
             kCVPixelFormatType_16BE565,
             kCVPixelFormatType_16LE565,
             kCVPixelFormatType_24RGB,
             kCVPixelFormatType_24BGR,
             kCVPixelFormatType_32ARGB,
             kCVPixelFormatType_32BGRA,
             kCVPixelFormatType_32ABGR,
             kCVPixelFormatType_32RGBA,
             kCVPixelFormatType_64ARGB,
             kCVPixelFormatType_48RGB,
             kCVPixelFormatType_32AlphaGray,
             kCVPixelFormatType_16Gray,
             kCVPixelFormatType_30RGB,
             kCVPixelFormatType_422YpCbCr8,
             kCVPixelFormatType_4444YpCbCrA8,
             kCVPixelFormatType_4444YpCbCrA8R,
             kCVPixelFormatType_4444AYpCbCr8,
             kCVPixelFormatType_4444AYpCbCr16,
             kCVPixelFormatType_444YpCbCr8,
             kCVPixelFormatType_422YpCbCr16,
             kCVPixelFormatType_422YpCbCr10,
             kCVPixelFormatType_444YpCbCr10,
             kCVPixelFormatType_420YpCbCr8Planar,
             kCVPixelFormatType_420YpCbCr8PlanarFullRange,
             kCVPixelFormatType_422YpCbCr_4A_8BiPlanar,
             kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
             kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
             kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
             kCVPixelFormatType_420YpCbCr10BiPlanarFullRange,
             kCVPixelFormatType_422YpCbCr8_yuvs,
             kCVPixelFormatType_422YpCbCr8FullRange,
             kCVPixelFormatType_OneComponent8,
             kCVPixelFormatType_TwoComponent8,
             kCVPixelFormatType_OneComponent16Half,
             kCVPixelFormatType_OneComponent32Float,
             kCVPixelFormatType_TwoComponent16Half,
             kCVPixelFormatType_TwoComponent32Float,
             kCVPixelFormatType_64RGBAHalf,
             kCVPixelFormatType_128RGBAFloat,
             kCVPixelFormatType_Lossy_32BGRA,
             kCVPixelFormatType_Lossless_32BGRA,
             kCVPixelFormatType_Lossy_420YpCbCr8BiPlanarFullRange,
             kCVPixelFormatType_Lossy_420YpCbCr8BiPlanarVideoRange,
             kCVPixelFormatType_Lossless_420YpCbCr8BiPlanarFullRange,
             kCVPixelFormatType_Lossless_420YpCbCr8BiPlanarVideoRange,
             kCVPixelFormatType_Lossy_420YpCbCr10PackedBiPlanarVideoRange,
             kCVPixelFormatType_Lossy_422YpCbCr10PackedBiPlanarVideoRange,
             kCVPixelFormatType_Lossless_420YpCbCr10PackedBiPlanarVideoRange,
             kCVPixelFormatType_Lossless_422YpCbCr10PackedBiPlanarVideoRange:
            return false
        default:
            return true
        }
    }

    var configurationBox: Data? {
        guard let atoms = CMFormatDescriptionGetExtension(self, extensionKey: kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms) as? NSDictionary else {
            return nil
        }
        switch mediaSubType {
        case .h264:
            return atoms["avcC"] as? Data
        case .hevc:
            return atoms["hvcC"] as? Data
        default:
            return nil
        }
    }
}
