import Foundation
import HaishinKit
@preconcurrency import Network
import Testing

@testable import RTCHaishinKit

@Suite struct HTTPSessionTests {
    @Test func closingWhileNegotiatingDoesNotEnableASecondAttempt() async throws {
        let server = try OfferGateServer()
        defer { server.stop() }
        let uri = try await server.start()
        let session = HTTPSessionFactory().make(uri, mode: .playback, configuration: nil)
        let connection = Task { try await session.connect { } }
        defer { connection.cancel() }
        for _ in 0..<250 {
            if server.capturedOffer() != nil { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let offer = try #require(server.capturedOffer())
        #expect(offer.contains("a=ice-ufrag:"))
        #expect(offer.contains("a=candidate:"))
        #expect(offer.contains("m=audio"))
        #expect(offer.contains("m=video"))
        #expect(offer.components(separatedBy: "a=recvonly").count == 3)
        try await session.close()
        // A second connect must remain a no-op until the first attempt has finished.
        let (completions, completion) = AsyncStream<Bool>.makeStream()
        let secondConnection = Task {
            do { try await session.connect { }; completion.yield(true) }
            catch { completion.yield(false) }
            completion.finish()
        }
        defer { secondConnection.cancel() }
        let returnedWithoutAnotherAttempt = await withTaskGroup(of: Bool.self) { group in
            group.addTask { for await result in completions { return result }; return false }
            group.addTask { try? await Task.sleep(nanoseconds: 1_000_000_000); return false }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
        #expect(returnedWithoutAnotherAttempt)
        #expect(server.connectionCount() == 1)
        server.rejectOffer()
        await #expect {
            try await connection.value
        } throws: { error in
            (error as? URLError)?.code == .badServerResponse
        }
        #expect(await session.connected == false)
    }

    @Test(arguments:
 ["http:/localhost/whep", "https:/localhost/whep", "whep:/localhost/live", "https://", "https:///whep"])
    func rejectsMalformedURL(_ value: String) async throws {
        let uri = try #require(URL(string: value))
        for mode in [StreamSessionMode.publish, .playback] {
            let session = HTTPSessionFactory().make(uri, mode: mode, configuration: nil)
            await #expect {
                try await session.connect { }
            } throws: { error in
                (error as? URLError)?.code == .badURL
            }
            #expect(await session.connected == false)
            var states = await session.readyState.makeAsyncIterator()
            #expect(await states.next() == .closed)
        }
    }
}

/// Loopback-only HTTP fixture that holds a POST until the test checks the close contract.
private final class OfferGateServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "haishinkit.http-offer-test")
    private let lock = NSLock()
    private var offer: String?
    private var count = 0
    private var connections: [NWConnection] = []
    private var received = Data()

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        listener = try NWListener(using: parameters)
    }

    func start() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [listener] state in
                switch state {
                case .ready:
                    listener.stateUpdateHandler = nil
                    guard let port = listener.port, let url = URL(string: "http://127.0.0.1:\(port.rawValue)/stream/whep") else {
                        continuation.resume(throwing: URLError(.badURL)); return
                    }
                    continuation.resume(returning: url)
                case .failed(let error):
                    listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { connection.cancel(); return }
                self.lock.lock(); self.count += 1; self.lock.unlock()
                self.connections.append(connection)
                connection.start(queue: self.queue)
                self.read(connection)
            }
            listener.start(queue: queue)
        }
    }

    private func read(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, complete, error in
            guard let self else { return }
            if let data { self.received.append(data) }
            let separator = Data("\r\n\r\n".utf8)
            if let boundary = self.received.range(of: separator) {
                let header = String(decoding: self.received[..<boundary.lowerBound], as: UTF8.self)
                let length = header.components(separatedBy: "\r\n").first { $0.lowercased().hasPrefix("content-length:") }
                    .flatMap { Int($0.split(separator: ":", maxSplits: 1)[1].trimmingCharacters(in: .whitespaces)) }
                if let length, self.received.count - boundary.upperBound >= length {
                    let body = self.received[boundary.upperBound..<(boundary.upperBound + length)]
                    self.lock.lock(); self.offer = String(decoding: body, as: UTF8.self); self.lock.unlock()
                    return
                }
            }
            if !complete && error == nil { self.read(connection) }
        }
    }

    func capturedOffer() -> String? { lock.lock(); defer { lock.unlock() }; return offer }
    func connectionCount() -> Int { lock.lock(); defer { lock.unlock() }; return count }
    func rejectOffer() {
        queue.async { [self] in
            for connection in connections { connection.send(content: Data("HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8),
                             completion: .contentProcessed { _ in connection.cancel() }) }
        }
    }
    func stop() { listener.cancel(); queue.async { [self] in connections.forEach { $0.cancel() } } }
}
