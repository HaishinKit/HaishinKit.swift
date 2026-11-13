import Foundation
import HaishinKit
import Network

final actor RTMPSocket {
    static let defaultWindowSizeC = Int(UInt8.max)
    typealias ReceivedData = (data: Data, receivedAt: DispatchTime)

    enum Error: Swift.Error {
        case invalidState
        case endOfStream
        case connectionTimedOut
        case connectionNotEstablished(_ error: NWError?)
    }

    private(set) var pathReport: NWConnection.DataTransferReport.PathReport?
    private var timeout: UInt64 = 15
    private var connected = false
    private var windowSizeC = RTMPSocket.defaultWindowSizeC
    private var securityLevel: StreamSocketSecurityLevel = .none
    private var totalBytesIn = 0
    private var queueBytesOut = 0
    private var totalBytesOut = 0
    private var parameters: NWParameters = .tcp
    private var dataTransferReport: NWConnection.PendingDataTransferReport?
    private var connection: NWConnection? {
        didSet {
            oldValue?.viabilityUpdateHandler = nil
            oldValue?.stateUpdateHandler = nil
            oldValue?.forceCancel()
        }
    }
    private var outputs: AsyncStream<Data>.Continuation? {
        didSet {
            oldValue?.finish()
        }
    }
    private var qualityOfService: DispatchQoS = .userInitiated
    private var continuation: CheckedContinuation<Void, any Swift.Error>?
    private lazy var networkQueue = DispatchQueue(label: "com.haishinkit.HaishinKit.RTMPSocket.network", qos: qualityOfService)

    init() {
    }

    init(qualityOfService: DispatchQoS, securityLevel: StreamSocketSecurityLevel, requiredInterfaceType: NWInterface.InterfaceType? = nil) {
        self.qualityOfService = qualityOfService
        switch securityLevel {
        case .ssLv2, .ssLv3, .tlSv1, .negotiatedSSL:
            parameters = .tls
        default:
            parameters = .tcp
        }
        if let requiredInterfaceType {
            parameters.requiredInterfaceType = requiredInterfaceType
        }
    }

    func connect(_ name: String, port: Int) async throws {
        guard !connected else {
            throw Error.invalidState
        }
        totalBytesIn = 0
        totalBytesOut = 0
        queueBytesOut = 0
        pathReport = nil
        do {
            let connection = NWConnection(to: NWEndpoint.hostPort(host: .init(name), port: .init(integerLiteral: NWEndpoint.Port.IntegerLiteralType(port))), using: parameters)
            self.connection = connection
            try await withCheckedThrowingContinuation { (checkedContinuation: CheckedContinuation<Void, Swift.Error>) in
                self.continuation = checkedContinuation
                Task {
                    try? await Task.sleep(nanoseconds: timeout * 1_000_000_000)
                    guard let continuation else {
                        return
                    }
                    continuation.resume(throwing: Error.connectionTimedOut)
                    self.continuation = nil
                    close()
                }
                connection.stateUpdateHandler = { state in
                    Task { await self.stateDidChange(to: state) }
                }
                connection.viabilityUpdateHandler = { viability in
                    Task { await self.viabilityDidChange(to: viability) }
                }
                connection.start(queue: networkQueue)
            }
        } catch {
            throw error
        }
    }

    @discardableResult
    func send(_ data: Data) -> DispatchTime? {
        guard connected, let outputs else {
            return nil
        }
        queueBytesOut += data.count
        let queuedAt = DispatchTime.now()
        outputs.yield(data)
        return queuedAt
    }

    func send(_ iterator: AnyIterator<Data>) {
        guard connected else {
            return
        }
        for data in iterator {
            queueBytesOut += data.count
            outputs?.yield(data)
        }
    }

    func send(_ chunks: [Data]) {
        guard connected else {
            return
        }
        for data in chunks {
            queueBytesOut += data.count
            outputs?.yield(data)
        }
    }

    func recv() -> AsyncStream<ReceivedData> {
        AsyncStream<ReceivedData> { continuation in
            Task {
                do {
                    while connected {
                        let received = try await recv()
                        continuation.yield(received)
                        totalBytesIn += received.data.count
                    }
                } catch {
                    continuation.finish()
                }
            }
        }
    }

    func close(_ error: NWError? = nil) {
        guard connection != nil else {
            return
        }
        if let continuation {
            continuation.resume(throwing: Error.connectionNotEstablished(error))
            self.continuation = nil
        }
        connected = false
        outputs = nil
        connection = nil
        continuation = nil
        dataTransferReport = nil
        pathReport = nil
    }

    private func stateDidChange(to state: NWConnection.State) {
        switch state {
        case .ready:
            logger.info("Connection is ready.")
            connected = true
            let (stream, continuation) = AsyncStream<Data>.makeStream()
            Task {
                for await data in stream where connected {
                    try await send(data)
                    totalBytesOut += data.count
                    queueBytesOut -= data.count
                }
            }
            self.outputs = continuation
            self.dataTransferReport = connection?.startDataTransferReport()
            self.continuation?.resume()
            self.continuation = nil
        case .waiting(let error):
            logger.warn("Connection waiting:", error)
            close(error)
        case .setup:
            logger.debug("Connection is setting up.")
        case .preparing:
            logger.debug("Connection is preparing.")
        case .failed(let error):
            logger.warn("Connection failed:", error)
            close(error)
        case .cancelled:
            logger.info("Connection cancelled.")
            close()
        @unknown default:
            logger.error("Unknown connection state.")
        }
    }

    private func viabilityDidChange(to viability: Bool) {
        logger.info("Connection viability changed to ", viability)
        if viability == false {
            close()
        }
    }

    private func send(_ data: Data) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            guard let connection else {
                continuation.resume(throwing: Error.invalidState)
                return
            }
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume()
            })
        }
    }

    private func updateTransportStatistics() async {
        guard let connection, let dataTransferReport else {
            return
        }
        self.dataTransferReport = connection.startDataTransferReport()
        let report = await withCheckedContinuation { continuation in
            dataTransferReport.collect(queue: networkQueue) { report in
                continuation.resume(returning: report)
            }
        }
        guard connected else {
            return
        }
        pathReport = report.aggregatePathReport
    }

    private func recv() async throws -> ReceivedData {
        return try await withCheckedThrowingContinuation { continuation in
            guard let connection else {
                continuation.resume(throwing: Error.invalidState)
                return
            }
            connection.receive(minimumIncompleteLength: 0, maximumLength: windowSizeC) { content, _, _, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                if let content {
                    continuation.resume(returning: (content, .now()))
                } else {
                    continuation.resume(throwing: Error.endOfStream)
                }
            }
        }
    }
}

extension RTMPSocket: NetworkTransportReporter {
    // MARK: NetworkTransportReporter
    func makeNetworkMonitor() async -> NetworkMonitor {
        return .init(self)
    }

    func makeNetworkTransportReport() async -> NetworkTransportReport {
        await updateTransportStatistics()
        return .init(queueBytesOut: queueBytesOut, totalBytesIn: totalBytesIn, totalBytesOut: totalBytesOut)
    }
}
