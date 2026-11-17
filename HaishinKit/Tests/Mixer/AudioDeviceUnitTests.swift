import AVFoundation
import Foundation
import Testing

@testable import HaishinKit

@Suite(.disabled(if: TestEnvironment.isCI))
struct AudioDeviceUnitTests {
    @Test func release() {
        weak var weakDevice: AudioDeviceUnit?
        _ = {
            let device = try! AudioDeviceUnit(0, device: AVCaptureDevice.default(for: .audio)!)
            weakDevice = device
        }()
        #expect(weakDevice == nil)
    }
}
