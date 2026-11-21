import Foundation
import Network

@available(iOS 16.0, macOS 13.0, tvOS 16.0, *)
typealias MoQTQUICStream = NWConnection

@available(iOS 16.0, macOS 13.0, tvOS 16.0, *)
final actor MoQTSocket {
    static let alpn = ["moqt-23"]

    private let group: NWConnectionGroup
    private let options: NWProtocolQUIC.Options
    private let queue = DispatchQueue(label: "com.haishinkit.MoQT")
    private let states: AsyncThrowingStream<Void, any Swift.Error>
    private let incoming: AsyncStream<NWConnection>
    private let datagrams: AsyncStream<Data>

    init(host: String, port: NWEndpoint.Port) {
        let endpoint = NWEndpoint.hostPort(host: .init(host), port: port)
        let options = NWProtocolQUIC.Options(alpn: Self.alpn)
        options.maxDatagramFrameSize = 65_535
        // Deliver datagrams to the group receive handler, separately from streams.
        options.isDatagram = true
        self.options = options
        let group = NWConnectionGroup(with: NWMultiplexGroup(to: endpoint), using: NWParameters(quic: options))
        self.group = group
        let (states, stateContinuation) = AsyncThrowingStream<Void, any Swift.Error>.makeStream()
        self.states = states
        let (incoming, streamContinuation) = AsyncStream<NWConnection>.makeStream()
        self.incoming = incoming
        let (datagrams, datagramContinuation) = AsyncStream<Data>.makeStream()
        self.datagrams = datagrams
        group.stateUpdateHandler = { state in
            switch state {
            case .ready:
                stateContinuation.yield(())
                stateContinuation.finish()
            case .failed(let error):
                stateContinuation.finish(throwing: error)
                streamContinuation.finish()
                datagramContinuation.finish()
            case .cancelled:
                stateContinuation.finish(throwing: CancellationError())
                streamContinuation.finish()
                datagramContinuation.finish()
            default:
                break
            }
        }
        group.newConnectionHandler = { [queue] stream in
            stream.start(queue: queue)
            if case .terminated = streamContinuation.yield(stream) { stream.cancel() }
        }
        group.setReceiveHandler { _, content, _ in
            if let content { datagramContinuation.yield(content) }
        }
    }

    func start() async throws {
        group.start(queue: queue)
        var iterator = states.makeAsyncIterator()
        guard try await iterator.next() != nil else { throw CancellationError() }
    }

    func openStream(_ direction: NWProtocolQUIC.Options.Direction) throws -> NWConnection {
        // Reuse the group's options so the extracted stream uses the established QUIC tunnel.
        options.isDatagram = false
        options.direction = direction
        guard let stream = group.extract(using: options) else { throw MoQTConnection.Error.invalidState }
        stream.start(queue: queue)
        return stream
    }

    func close() {
        group.cancel()
    }

    func receiveStreams(_ handler: @Sendable (NWConnection) async -> Void) async {
        for await stream in incoming {
            await handler(stream)
        }
    }

    func receiveDatagrams(_ handler: @Sendable (Data) async -> Void) async {
        for await datagram in datagrams {
            await handler(datagram)
        }
    }
}

@available(iOS 16.0, macOS 13.0, tvOS 16.0, *)
extension NWConnection {
    func send(_ data: Data, endOfStream: Bool = false) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Swift.Error>) in
                send(content: data, contentContext: endOfStream ? .finalMessage : .defaultMessage,
                     isComplete: true, completion: .contentProcessed { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                })
            }
        } onCancel: {
            self.cancel()
        }
    }

    var isBidirectional: Bool {
        let metadata = metadata(definition: NWProtocolQUIC.definition) as? NWProtocolQUIC.Metadata
        return metadata.map { $0.streamIdentifier & 2 == 0 } ?? false
    }
}

@available(iOS 16.0, macOS 13.0, tvOS 16.0, *)
struct MoQTStreamReader {
    let stream: NWConnection
    private var buffer = Data()
    private var ended = false

    init(_ stream: NWConnection) {
        self.stream = stream
    }

    mutating func read<Value>(_ decode: (inout MoQTPayload) throws -> Value) async throws -> Value? {
        while true {
            if !buffer.isEmpty {
                var payload = MoQTPayload(buffer)
                do {
                    let value = try decode(&payload)
                    buffer = payload.remainder()
                    return value
                } catch MoQTPayload.Error.eof {
                    if ended { throw MoQTPayload.Error.eof }
                }
            }
            if ended { return nil }
            let stream = self.stream
            let chunk: (Data?, Bool) = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    stream.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { content, _, complete, error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(returning: (content, complete))
                        }
                    }
                }
            } onCancel: {
                stream.cancel()
            }
            if let content = chunk.0 { buffer.append(content) }
            ended = chunk.1
        }
    }
}
