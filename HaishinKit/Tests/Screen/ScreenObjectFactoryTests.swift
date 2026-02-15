import AVFoundation
import Foundation
import Testing

@testable import HaishinKit

@ScreenActor
@Suite struct ScreenObjectFactoryTests {
    @Test func videoSnapshot() throws {
        let string = """
{"type":"video","id":"1771162233189358-1238207813","size":{"width":90,"height":160},"isVisible":true,"layoutMargin":{"top":16,"left":0,"bottom":0,"right":16},"horizontalAlignment":2,"verticalAlignment":0,"elements":{"track":"1"},"children":[]}
""".data(using: .utf8)!
        let snapshot = try JSONDecoder().decode(ScreenObjectSnapshot.self, from: string)
        let factory = ScreenObjectFactory()
        let videoScreenObject = factory.make(snapshot) as? VideoScreenObject
        #expect(videoScreenObject?.track == 1)
        #expect(videoScreenObject?.horizontalAlignment == .right)
        #expect(videoScreenObject?.verticalAlignment == .top)
        #expect(videoScreenObject?.size == .init(width: 90, height: 160))
    }
}
