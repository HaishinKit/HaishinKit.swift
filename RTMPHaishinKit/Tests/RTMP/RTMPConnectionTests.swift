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

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func incompleteConnectionTimesOut(afterHandshake: Bool) async throws {
        let server = try await silentServer()
        defer { server.listener.cancel() }
        let connection = RTMPConnection(timeout: 1)
        let attempt = Task { try await connection.connect(server.url) }
        var peers = server.peers.makeAsyncIterator()
        let peer = try #require(await peers.next())
        peer.start(queue: server.queue)
        defer { peer.cancel() }
        try await receive(1 + RTMPHandshake.sigSize, from: peer)
        if afterHandshake {
            var data = Data(count: 1 + 2 * RTMPHandshake.sigSize)
            data[0] = RTMPHandshake.protocolVersion
            try await send(data, to: peer)
            try await receive(RTMPHandshake.sigSize, from: peer)
            try await receive(1, from: peer)
        }
        switch await attempt.result {
        case .success: Issue.record("A silent server must not connect")
        case .failure(let error):
            guard case RTMPConnection.Error.connectionTimedOut = error else {
                Issue.record("Unexpected timeout error: \(error)")
                return
            }
        }
        #expect(await connection.uri == nil)
        #expect(await connection.connected == false)
    }

    @Test(.timeLimit(.minutes(1)))
    func cancelledHandshakeClosesTransport() async throws {
        let server = try await silentServer()
        defer { server.listener.cancel() }
        let connection = RTMPConnection(timeout: 5)
        let attempt = Task { try await connection.connect(server.url) }
        var peers = server.peers.makeAsyncIterator()
        let peer = try #require(await peers.next())
        peer.start(queue: server.queue)
        defer { peer.cancel() }
        try await receive(1 + RTMPHandshake.sigSize, from: peer)
        attempt.cancel()
        switch await attempt.result {
        case .success: Issue.record("Cancelled handshake succeeded")
        case .failure(let error): #expect(error is CancellationError)
        }
        #expect(await connection.uri == nil)
        #expect(await connection.connected == false)
    }

    @Test(.timeLimit(.minutes(1)))
    func closingHandshakeAllowsAnotherAttempt() async throws {
        let server = try await silentServer()
        defer { server.listener.cancel() }
        let connection = RTMPConnection(timeout: 1)
        var peers = server.peers.makeAsyncIterator()
        let first = Task { try await connection.connect(server.url) }
        let peer1 = try #require(await peers.next())
        peer1.start(queue: server.queue)
        defer { peer1.cancel() }
        try await receive(1 + RTMPHandshake.sigSize, from: peer1)
        try await Task.sleep(nanoseconds: 600_000_000)
        try await connection.close()
        _ = await first.result
        let second = Task { try await connection.connect(server.url) }
        let peer2 = try #require(await peers.next())
        peer2.start(queue: server.queue)
        defer { peer2.cancel() }
        try await receive(1 + RTMPHandshake.sigSize, from: peer2)
        try await Task.sleep(nanoseconds: 600_000_000)
        #expect(await connection.uri != nil)
        try await connection.close()
        _ = await second.result
        #expect(await connection.uri == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func sessionCanCloseBeforeHandshakeCompletes() async throws {
        let server = try await silentServer()
        defer { server.listener.cancel() }
        let session = RTMPSessionFactory().make(try #require(URL(string: server.url + "/stream")), mode: .publish, configuration: nil)
        let attempt = Task { try await session.connect {} }
        var peers = server.peers.makeAsyncIterator()
        let peer = try #require(await peers.next())
        peer.start(queue: server.queue)
        defer { peer.cancel() }
        try await receive(1 + RTMPHandshake.sigSize, from: peer)
        try await session.close()
        switch await attempt.result {
        case .success: Issue.record("Closed session connected")
        case .failure(let error): #expect(error is CancellationError)
        }
        #expect(await session.connected == false)
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func successfulConnectCancelsItsDeadline(afterPartialReply: Bool) async throws {
        let server = try await silentServer()
        defer { server.listener.cancel() }
        let connection = RTMPConnection(timeout: 1)
        var peers = server.peers.makeAsyncIterator()
        if afterPartialReply {
            let abandoned = Task { try await connection.connect(server.url) }
            let oldPeer = try #require(await peers.next())
            oldPeer.start(queue: server.queue)
            defer { oldPeer.cancel() }
            try await receive(1 + RTMPHandshake.sigSize, from: oldPeer)
            var handshake = Data(count: 1 + 2 * RTMPHandshake.sigSize)
            handshake[0] = RTMPHandshake.protocolVersion
            try await send(handshake, to: oldPeer)
            try await receive(RTMPHandshake.sigSize, from: oldPeer)
            try await receive(1, from: oldPeer)
            // A partial chunk header must not become the next connection's prefix.
            try await send(Data([3, 0, 0, 0, 0]), to: oldPeer)
            _ = await abandoned.result
            #expect(await connection.connected == false)
        }
        let attempt = Task { try await connection.connect(server.url) }
        let peer = try #require(await peers.next())
        peer.start(queue: server.queue)
        defer { peer.cancel() }
        try await receive(1 + RTMPHandshake.sigSize, from: peer)
        var handshake = Data(count: 1 + 2 * RTMPHandshake.sigSize)
        handshake[0] = RTMPHandshake.protocolVersion
        try await send(handshake, to: peer)
        try await receive(RTMPHandshake.sigSize, from: peer)
        try await receive(1, from: peer)
        let reply = RTMPCommandMessage(streamId: 0, transactionId: 1, objectEncoding: .amf0,
            commandName: "_result", commandObject: nil,
            arguments: [["level": "status", "code": "NetConnection.Connect.Success"] as AMFObject])
        let buffer = RTMPChunkBuffer()
        for chunk in buffer.putMessage(.zero, chunkStreamId: 3, message: reply) {
            try await send(chunk, to: peer)
        }
        _ = try await attempt.value
        try await Task.sleep(nanoseconds: 1_200_000_000)
        #expect(await connection.connected)
        try await connection.close()
    }

    @Test(.timeLimit(.minutes(1)))
    func tlsSetupUsesTheConnectionDeadline() async throws {
        let server = try await silentServer()
        defer { server.listener.cancel() }
        let connection = RTMPConnection(timeout: 1)
        let attempt = Task { try await connection.connect(server.url.replacingOccurrences(of: "rtmp:", with: "rtmps:")) }
        var peers = server.peers.makeAsyncIterator()
        let peer = try #require(await peers.next())
        peer.start(queue: server.queue)
        defer { peer.cancel() }
        // The TCP peer deliberately sends no TLS response.
        switch await attempt.result {
        case .success: Issue.record("Silent TLS peer connected")
        case .failure(let error):
            guard case RTMPConnection.Error.connectionTimedOut = error else {
                Issue.record("Unexpected TLS deadline error: \(error)")
                return
            }
        }
        #expect(await connection.uri == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellationBeforeConnectStartsIsClean() async throws {
        let connection = RTMPConnection(timeout: 1)
        let attempt = Task {
            return try await connection.connect("rtmp://127.0.0.1:19369/live")
        }
        attempt.cancel()
        _ = await attempt.result
        #expect(await connection.connected == false)
        #expect(await connection.uri == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func receiveOnClosedSocketFinishes() async {
        let socket = RTMPSocket()
        await socket.close()
        var values = await socket.recv().makeAsyncIterator()
        #expect(await values.next() == nil)
    }

    private func silentServer() async throws -> (listener: NWListener, queue: DispatchQueue, peers: AsyncStream<NWConnection>, url: String) {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        let queue = DispatchQueue(label: "RTMPConnectionTests.silent")
        let (states, updates) = AsyncStream<NWListener.State>.makeStream()
        let (peers, arrivals) = AsyncStream<NWConnection>.makeStream()
        listener.stateUpdateHandler = { updates.yield($0) }
        listener.newConnectionHandler = { arrivals.yield($0) }
        listener.start(queue: queue)
        for await state in states {
            if case .ready = state { break }
            if case .failed(let error) = state { listener.cancel(); throw error }
        }
        let port = try #require(listener.port)
        return (listener, queue, peers, "rtmp://127.0.0.1:\(port.rawValue)/live")
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
