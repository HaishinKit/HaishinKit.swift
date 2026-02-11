@preconcurrency import Combine
import Foundation
import HaishinKit

actor SRTSession: StreamSession {
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

    private let uri: URL
    private let mode: StreamSessionMode
    private var retryCount: Int = 0
    private var maxRetryCount = kStreamSession_maxRetryCount
    private lazy var connection = SRTConnection()
    private lazy var _stream: SRTStream = {
        SRTStream(connection: connection)
    }()
    private var cancellables: Set<AnyCancellable> = []
    private var disconnctedTask: Task<Void, any Error>? {
        didSet {
            oldValue?.cancel()
        }
    }

    init(uri: URL, mode: StreamSessionMode, configuration: (any StreamSessionConfiguration)?) {
        self.uri = uri
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
        do {
            try await connection.connect(uri)
        } catch {
            if let error = error as? SRTConnection.Error {
                switch error {
                case .failedToConnect(let reason):
                    // If the timeout has expired, there is no prospect of successfully reconnecting
                    // even if a retry is attempted, so no retry will be performed.
                    guard reason == .timeout else {
                        retryCount = 0
                        _readyState.value = .closed
                        throw error
                    }
                default:
                    break
                }
            }
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
        _readyState.value = .open
        retryCount = 0
        switch mode {
        case .playback:
            await _stream.play()
        case .publish:
            await _stream.publish()
        }
        disconnctedTask = Task {
            cancellables.removeAll()
            await connection.$connected.sink {
                if $0 == false {
                    disconnected()
                }
            }.store(in: &cancellables)
        }
    }

    func close() async throws {
        guard await connection.connected else {
            return
        }
        _readyState.value = .closing
        await connection.close()
        retryCount = 0
        _readyState.value = .closed
    }
}
