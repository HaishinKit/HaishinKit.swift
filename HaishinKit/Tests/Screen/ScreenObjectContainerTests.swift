import AVFoundation
import Foundation
import Testing

@testable import HaishinKit

@ScreenActor
@Suite struct ScreenObjectContainerTests {
    @Test func lookUpVideoTrackScreenObject() {
        let container1 = ScreenObjectContainer()

        let videoTrack1 = VideoScreenObject()
        let videoTrack2 = VideoScreenObject()

        try? container1.addChild(videoTrack1)
        try? container1.addChild(videoTrack2)

        let videoTracks1 = container1.getScreenObjects() as [VideoScreenObject]
        #expect(videoTracks1.count == 2)

        let container2 = ScreenObjectContainer()
        let videoTrack3 = VideoScreenObject()
        try? container2.addChild(videoTrack3)
        try? container1.addChild(container2)

        let videoTracks2 = container1.getScreenObjects() as [VideoScreenObject]
        #expect(videoTracks2.count == 3)
    }
}
