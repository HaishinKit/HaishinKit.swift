import AVFoundation
import Foundation
import Testing

@testable import HaishinKit

@Suite struct VideoDeviceUnitTests {
    @Test func release() {
        weak var weakDevice: VideoDeviceUnit?
        _ = {
            guard let videoDevice = AVCaptureDevice.default(for: .video) else {
                return
            }
            let device = try? VideoDeviceUnit(0, device: videoDevice)
            weakDevice = device
        }()
        #expect(weakDevice == nil)
    }
}
