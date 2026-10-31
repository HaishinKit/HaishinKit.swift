import AVFoundation
import Testing

@testable import HaishinKit

@Suite struct AVCaptureDeviceFormatExtensionTests {
    @Test(arguments: [24.0, 30.0, 50.0, 59.0, 60.0])
    func fixedFrameRate(frameRate: Float64) {
        #expect(AVCaptureDevice.Format.isFrameRateSupported(frameRate, in: [30.0...30.0]) == (frameRate == 30.0))
    }

    @Test(arguments: [24.0, 29.97, 30.0, 50.0, 59.94, 60.0])
    func multipleFixedFrameRates(frameRate: Float64) {
        let ranges = [30.0...30.0, 50.0...50.0, 59.94...59.94]
        let expected = [30.0, 50.0, 59.94].contains(frameRate)
        #expect(AVCaptureDevice.Format.isFrameRateSupported(frameRate, in: ranges) == expected)
    }

    @Test(arguments: [(14.0, false), (15.0, true), (24.0, true), (29.97, true), (30.0, true), (31.0, false)])
    func variableFrameRate(frameRate: Float64, expected: Bool) {
        #expect(AVCaptureDevice.Format.isFrameRateSupported(frameRate, in: [15.0...30.0]) == expected)
    }

    @Test func laterRange() {
        #expect(AVCaptureDevice.Format.isFrameRateSupported(60, in: [15.0...30.0, 50.0...60.0]))
        #expect(AVCaptureDevice.Format.isFrameRateSupported(60, in: [15.0...30.0, 60.0...60.0]))
        #expect(AVCaptureDevice.Format.isFrameRateSupported(60, in: [30.0...30.0, 50.0...60.0]))
    }

    @Test func gapBetweenRanges() {
        #expect(!AVCaptureDevice.Format.isFrameRateSupported(40, in: [15.0...30.0, 50.0...60.0]))
        #expect(!AVCaptureDevice.Format.isFrameRateSupported(40, in: [30.0...30.0, 60.0...60.0]))
    }

    @Test func noRanges() {
        #expect(!AVCaptureDevice.Format.isFrameRateSupported(30, in: []))
    }

    @Test(arguments: [0.0, -30.0, Float64.nan, Float64.infinity, -Float64.infinity])
    func invalidFrameRate(frameRate: Float64) {
        #expect(!AVCaptureDevice.Format.isFrameRateSupported(frameRate, in: [30.0...30.0]))
        #expect(!AVCaptureDevice.Format.isFrameRateSupported(frameRate, in: [15.0...30.0]))
    }
}
