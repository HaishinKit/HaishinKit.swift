import Foundation
import Testing

import libsrt
@testable import SRTHaishinKit

@Suite struct SRTConnectionTests {
    @Test(arguments: ["srt:/", "srt:/localhost:9000", "srt:localhost:9000"])
    func rejectsMalformedURL(_ value: String) async throws {
        let uri = try #require(URL(string: value))
        let connection = SRTConnection()
        await #expect {
            try await connection.connect(uri)
        } throws: { error in
            guard case SRTConnection.Error.unsupportedUri(let value) = error else {
                return false
            }
            return value == uri
        }
        #expect(await connection.connected == false)
        #expect(await connection.uri == nil)
    }

    @Test func streamid_success() async throws {
        try await withListener("srt://:10000?streamid=test") { connection, accepting in
            try await connection.connect(URL(string: "srt://127.0.0.1:10000?streamid=test&conntimeo=1000"))
            try await accepting.value
            #expect(await connection.connected)
            let streamid = try await connection.getSocketOption(.streamid)
            #expect(streamid?.stringValue == "test")
        }
    }

    @Test func rejectsMismatchedPassphrase() async throws {
        try await withListener("srt://:10001?passphrase=listener-password") { connection, _ in
            await #expect(throws: SRTConnection.Error.self) {
                try await connection.connect(URL(string: "srt://127.0.0.1:10001?passphrase=different-password&conntimeo=1000"))
            }
            #expect(await connection.connected == false)
        }
    }

    private func withListener(
        _ uri: String,
        operation: (SRTConnection, Task<Void, any Error>) async throws -> Void
    ) async throws {
        let listener = SRTConnection()
        let connection = SRTConnection()
        let accepting = Task { try await listener.connect(URL(string: uri)) }
        do {
            // Wait for bind/listen before starting the caller, without blocking an executor thread.
            for _ in 0..<100 where await listener.uri == nil {
                try await Task.sleep(for: .milliseconds(10))
            }
            try #require(await listener.uri != nil)
            try await operation(connection, accepting)
        } catch {
            await connection.close()
            await listener.close()
            _ = await accepting.result
            throw error
        }
        await connection.close()
        await listener.close()
        _ = await accepting.result
    }
}
