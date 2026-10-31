import AVFoundation
import Foundation

#if os(macOS)
extension AVCaptureDevice.Format {
    var isMultiCamSupported: Bool {
        return true
    }
}
#elseif os(visionOS)
extension AVCaptureDevice.Format {
    var isMultiCamSupported: Bool {
        return false
    }
}
#endif

@available(tvOS 17.0, *)
extension AVCaptureDevice.Format {
    func isFrameRateSupported(_ frameRate: Float64) -> Bool {
        Self.isFrameRateSupported(frameRate, in: videoSupportedFrameRateRanges.map { $0.minFrameRate...$0.maxFrameRate })
    }

    static func isFrameRateSupported(_ frameRate: Float64, in ranges: [ClosedRange<Float64>]) -> Bool {
        ranges.contains { $0.contains(frameRate) }
    }
}
