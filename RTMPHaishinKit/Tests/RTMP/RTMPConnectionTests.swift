import Foundation
import Testing

@testable import RTMPHaishinKit

@Suite struct RTMPConnectionTests {
    @Test func releaseWhenClose() async throws {
        weak var weakConnection: RTMPConnection?
        _ = try? await {
            let connection = RTMPConnection()
            _ = try await connection.connect("rtmp://localhost:19350/live")
            try await connection.close()
            weakConnection = connection
        }()
        #expect(weakConnection == nil)
    }
}
