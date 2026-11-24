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
    private var generation = UUID()
    private var isConnecting = false
    private var connectionTask: Task<RTMPResponse, any Error>?
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
        guard !isConnecting, _readyState.value != .closing else { throw RTMPConnection.Error.invalidState }
        let id = generation
        isConnecting = true
        defer {
            if generation == id { isConnecting = false; connectionTask = nil }
        }
        guard await connection.connected == false else { return }
        guard generation == id, !Task.isCancelled else { throw CancellationError() }
        _readyState.value = .connecting
        disconnctedTask = nil
        while true {
            let task = Task { try await self.connection.connect(self.uri.command) }
            connectionTask = task
            do {
                _ = try await withTaskCancellationHandler {
                    try await task.value
                } onCancel: { task.cancel() }
                break
            } catch {
                guard generation == id else { throw CancellationError() }
                connectionTask = nil
                guard !Task.isCancelled else {
                    _readyState.value = .closed
                    throw CancellationError()
                }
                guard retryCount < maxRetryCount else {
                    retryCount = 0
                    _readyState.value = .closed
                    throw error
                }
                do {
                    try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(retryCount))) * 1_000_000_000)
                } catch {
                    if generation == id { _readyState.value = .closed }
                    throw error
                }
                guard generation == id, !Task.isCancelled else { throw CancellationError() }
                retryCount += 1
            }
        }
        do {
            guard generation == id, !Task.isCancelled else { throw CancellationError() }
            retryCount = 0
            switch mode {
            case .publish:
                _ = try await _stream.publish(uri.streamName)
            case .playback:
                _ = try await _stream.play(uri.streamName)
            }
            guard generation == id, !Task.isCancelled else { throw CancellationError() }
            _readyState.value = .open
        } catch {
            // Errors at the NetStream layer, such as incorrect stream names,
            // cannot be resolved by retrying, so they are thrown as exceptions.
            guard generation == id else { throw CancellationError() }
            try? await connection.close()
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
        guard _readyState.value != .closing else { return }
        generation = UUID()
        let pending = connectionTask
        pending?.cancel()
        connectionTask = nil
        _readyState.value = .closing
        disconnctedTask = nil
        if await connection.uri != nil { try? await connection.close() }
        _ = await pending?.result
        isConnecting = false
        retryCount = 0
        _readyState.value = .closed
    }
}
