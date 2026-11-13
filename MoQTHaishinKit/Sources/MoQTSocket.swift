import Foundation
import Network

@available(iOS 26.0, macOS 26.0, tvOS 26.0, visionOS 26.0, *)
typealias MoQTQUICStream = QUIC.Stream<QUICStream>

@available(iOS 26.0, macOS 26.0, tvOS 26.0, visionOS 26.0, *)
final class MoQTSocket: Sendable {
    static let alpn = ["moqt-23"]

    private let connection: NetworkConnection<QUIC>

    init(host: String, port: NWEndpoint.Port) {
        let endpoint = NWEndpoint.hostPort(host: .init(host), port: port)
        connection = NetworkConnection(to: endpoint) {
            QUIC(alpn: Self.alpn).maxDatagramFrameSize(65_535)
        }
    }

    func start() {
        _ = connection.start()
    }

    func openStream(_ direction: QUICStream.Directionality) async throws -> MoQTQUICStream {
        try await connection.openStream(directionality: direction)
    }

    func receiveStreams(_ handler: @escaping @Sendable (MoQTQUICStream) async -> Void) async throws {
        try await connection.inboundStreams(handler)
    }

    func receiveDatagrams(_ handler: @Sendable (Data) async -> Void) async throws {
        let datagrams = try await connection.datagrams
        while !Task.isCancelled {
            let message = try await datagrams.receive()
            await handler(message.content)
        }
    }
}

@available(iOS 26.0, macOS 26.0, tvOS 26.0, visionOS 26.0, *)
struct MoQTStreamReader {
    let stream: MoQTQUICStream
    private var buffer = Data()
    private var ended = false

    init(_ stream: MoQTQUICStream) {
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
            let chunk = try await stream.receive(atMost: 65_536)
            buffer.append(chunk.content)
            ended = chunk.metadata.endOfStream
        }
    }
}
