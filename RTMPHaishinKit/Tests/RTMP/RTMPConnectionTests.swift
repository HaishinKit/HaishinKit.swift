import Foundation
import Network
import Testing

@testable import RTMPHaishinKit

@Suite struct RTMPConnectionTests {
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

    @Test(.timeLimit(.minutes(1)), arguments: [true, false])
    func handshakeDurationIsRetainedUntilNextAttempt(fragmented: Bool) async throws {
        let listener = try NWListener(using: .tcp)
        let queue = DispatchQueue(label: "RTMPConnectionTests.handshake")
        let (states, stateUpdates) = AsyncStream<NWListener.State>.makeStream()
        let (peers, newPeers) = AsyncStream<NWConnection>.makeStream()
        listener.stateUpdateHandler = { state in stateUpdates.yield(state) }
        listener.newConnectionHandler = { peer in newPeers.yield(peer) }
        listener.start(queue: queue)
        defer { listener.cancel() }
        for await state in states {
            if case .ready = state { break }
            if case .failed(let error) = state { throw error }
        }
        let port = try #require(listener.port)
        let url = "rtmp://127.0.0.1:\(port.rawValue)/live"
        let connection = RTMPConnection()
        var connections = peers.makeAsyncIterator()
        let packetSize = RTMPHandshake.sigSize
        var serverHandshake = Data(count: 1 + 2 * packetSize)
        serverHandshake[0] = RTMPHandshake.protocolVersion

        let firstAttempt = Task { try await connection.connect(url) }
        let firstPeer = try #require(await connections.next())
        firstPeer.start(queue: queue)
        defer { firstPeer.cancel() }
        try await receive(1 + packetSize, from: firstPeer)
        #expect(await connection.handshakeDuration == nil)
        if fragmented {
            let split = 2 + packetSize
            try await send(Data(serverHandshake.prefix(split)), to: firstPeer)
            try await receive(packetSize, from: firstPeer)
            #expect(await connection.handshakeDuration == nil)
            try await send(Data(serverHandshake.dropFirst(split)), to: firstPeer)
        } else {
            try await send(serverHandshake, to: firstPeer)
            try await receive(packetSize, from: firstPeer)
        }
        // The RTMP connect command follows handshake completion.
        try await receive(1, from: firstPeer)
        let duration = try #require(await connection.handshakeDuration)
        #expect(duration > 0)
        try await connection.close()
        _ = await firstAttempt.result
        #expect(await connection.handshakeDuration == duration)

        let secondAttempt = Task { try await connection.connect(url) }
        let secondPeer = try #require(await connections.next())
        secondPeer.start(queue: queue)
        defer { secondPeer.cancel() }
        try await receive(1 + packetSize, from: secondPeer)
        try await send(Data(serverHandshake.prefix(2 + packetSize)), to: secondPeer)
        try await receive(packetSize, from: secondPeer)
        #expect(await connection.handshakeDuration == nil)
        try await connection.close()
        _ = await secondAttempt.result
    }

    private func receive(_ count: Int, from peer: NWConnection) async throws {
        let received = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, any Error>) in
            peer.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: data?.count ?? 0)
                }
            }
        }
        try #require(received == count)
    }

    private func send(_ data: Data, to peer: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            peer.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }
}
