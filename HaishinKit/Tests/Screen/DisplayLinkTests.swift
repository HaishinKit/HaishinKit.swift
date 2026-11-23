#if os(macOS)
import Foundation
import Testing

@testable import HaishinKit

@Suite struct DisplayLinkTests {
    @MainActor @Test(.enabled(if: !TestEnvironment.isCI))
    func defaultFrameRateAdvancesPlaybackClock() async {
        let choreographer = DisplayLinkChoreographer()
        let frames = choreographer.updateFrames
        choreographer.startRunning()
        defer { choreographer.stopRunning() }
        let timeout = Task { @MainActor in
            try await Task.sleep(for: .seconds(2))
            choreographer.stopRunning()
        }
        defer { timeout.cancel() }
        var receivedFrame = false
        for await frame in frames {
            receivedFrame = true
            #expect(frame.targetTimestamp > frame.timestamp)
            break
        }
        #expect(receivedFrame)
    }
}
#endif
