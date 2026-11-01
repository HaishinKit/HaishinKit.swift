import Foundation
import Network
import Testing

@testable import RTMPHaishinKit

@Suite struct RTMPConnectionTests {
    @Test func requiredInterfaceType() async {
        #expect(await RTMPConnection().requiredInterfaceType == nil)
        let connection = RTMPConnection(requiredInterfaceType: .cellular)
        #expect(await connection.requiredInterfaceType == .cellular)
    }

    @Test(arguments: ["rtmp:/", "rtmps:/", "rtmp:/localhost/live", "rtmps:/localhost/live", "rtmp:///live", "rtmps://"])
    func rejectsMalformedURL(_ command: String) async {
        let connection = RTMPConnection()
        await #expect {
            _ = try await connection.connect(command)
        } throws: { error in
            guard case RTMPConnection.Error.unsupportedCommand(let value) = error else {
                return false
            }
            return value == command
        }
        #expect(await connection.connected == false)
        #expect(await connection.uri == nil)
    }

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
