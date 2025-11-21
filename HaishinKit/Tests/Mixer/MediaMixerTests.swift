import AVFoundation
import Foundation
import Testing

@testable import HaishinKit

@Suite struct MediaMixerTests {
    @Test func videoConfiguration() async throws {
        let mixer = MediaMixer()
        await #expect(throws: (MediaMixer.Error).self) {
            try await mixer.configuration(video: 0) { _ in }
        }
        try await mixer.attachVideo(AVCaptureDevice.default(for: .video), track: 0) { unit in
            #expect(throws: (any Error).self) {
                try unit.setFrameRate(60)
            }
        }
        try await mixer.configuration(video: 0) { _ in }
    }

    @Test func release() async {
        weak var weakMixer: MediaMixer?
        _ = await {
            let mixer = MediaMixer(captureSessionMode: .manual)
            await mixer.startRunning()
            try? await Task.sleep(nanoseconds: 1)
            await mixer.stopRunning()
            try? await Task.sleep(nanoseconds: 1)
            weakMixer = mixer
        }()
        #expect(weakMixer == nil)
    }

    @Test func release_with_multimode() async {
        weak var weakMixer: MediaMixer?
        _ = await {
            let mixer = MediaMixer(captureSessionMode: .multi)
            await mixer.startRunning()
            try? await Task.sleep(nanoseconds: 1)
            await mixer.stopRunning()
            try? await Task.sleep(nanoseconds: 1)
            weakMixer = mixer
        }()
        #expect(weakMixer == nil)
    }

    @Test func currentFrameRate() async throws {
        let mixer = MediaMixer()
        try await mixer.setFrameRate(60)
        #expect(await mixer.frameRate == 60)
    }
}
