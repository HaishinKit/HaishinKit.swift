import Foundation
import HaishinKit

actor RTMPSession: StreamSession {
    var connected: Bool {
        get async {
            await connection.connected
        }
    }

    @AsyncStreamed(.closed)
    private(set) var readyState: AsyncStream<StreamSessionReadyState>

    var stream: any StreamConvertible {
        _stream
    }

    private let uri: RTMPURL
    private let mode: StreamSessionMode
    private var retryCount: Int = 0
    private var maxRetryCount = kStreamSession_maxRetryCount
    private lazy var connection: RTMPConnection = {
        switch mode {
        case .publish:
            return RTMPConnection()
        case .playback:
            return RTMPConnection(flashVer: "MAC 9,0,124,2")
        }
    }()
    private lazy var _stream: RTMPStream = {
        switch mode {
        case .publish:
            return RTMPStream(connection: connection, fcPublishName: uri.streamName)
        case .playback:
            return RTMPStream(connection: connection)
        }
    }()
    private var disconnctedTask: Task<Void, any Error>? {
        didSet {
            oldValue?.cancel()
        }
    }

    init(uri: URL, mode: StreamSessionMode, configuration: (any StreamSessionConfiguration)?) {
        self.uri = RTMPURL(url: uri)
        self.mode = mode
    }

    func setMaxRetryCount(_ maxRetryCount: Int) {
        self.maxRetryCount = maxRetryCount
    }

    func connect(_ disconnected: @Sendable @escaping () -> Void) async throws {
        guard await connection.connected == false else {
            return
        }
        _readyState.value = .connecting
        disconnctedTask = nil
        // Retry handling at the TCP/IP level and during RTMP connection.
        do {
            _ = try await connection.connect(uri.command)
        } catch {
            guard retryCount < maxRetryCount else {
                retryCount = 0
                _readyState.value = .closed
                throw error
            }
            // It is being delayed using backoff for congestion control.
            try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(retryCount))) * 1_000_000_000)
            retryCount += 1
            try await connect(disconnected)
        }
        do {
            retryCount = 0
            switch mode {
            case .publish:
                _ = try await _stream.publish(uri.streamName)
            case .playback:
                _ = try await _stream.play(uri.streamName)
            }
            _readyState.value = .open
        } catch {
            // Errors at the NetStream layer, such as incorrect stream names,
            // cannot be resolved by retrying, so they are thrown as exceptions.
            try await connection.close()
            _readyState.value = .closed
            throw error
        }
        disconnctedTask = Task {
            for await event in await connection.status {
                switch event.code {
                case RTMPConnection.Code.connectClosed.rawValue:
                    _readyState.value = .closed
                    disconnected()
                default:
                    break
                }
            }
        }
    }

    func close() async throws {
        guard await connection.connected else {
            return
        }
        _readyState.value = .closing
        disconnctedTask = nil
        try await connection.close()
        retryCount = 0
        _readyState.value = .closed
    }
}
