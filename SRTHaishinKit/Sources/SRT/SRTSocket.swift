import Foundation
import HaishinKit
import libsrt
import Logboard

final actor SRTSocket {
    static let payloadSize: Int = 1316

    enum Error: Swift.Error {
        case notConnected
        case invalidArgument(_ message: String)
        case rejected(_ reason: SRTRejectReason)
        case illegalState(_ message: String)
    }

    enum Status: Int, CustomDebugStringConvertible {
        case unknown
        case `init`
        case opened
        case listening
        case connecting
        case connected
        case broken
        case closing
        case closed
        case nonexist

        var debugDescription: String {
            switch self {
            case .unknown:
                return "unknown"
            case .`init`:
                return "init"
            case .opened:
                return "opened"
            case .listening:
                return "listening"
            case .connecting:
                return "connecting"
            case .connected:
                return "connected"
            case .broken:
                return "broken"
            case .closing:
                return "closing"
            case .closed:
                return "closed"
            case .nonexist:
                return "nonexist"
            }
        }

        init?(_ status: SRT_SOCKSTATUS) {
            self.init(rawValue: Int(status.rawValue))
            defer {
                logger.trace(debugDescription)
            }
        }
    }

    var inputs: AsyncStream<Data> {
        AsyncStream<Data> { continuation in
            // If Task.detached is not used, closing will result in a deadlock.
            Task.detached {
                while await self.connected {
                    let result = await self.recvmsg()
                    if 0 <= result {
                        continuation.yield(await self.incomingBuffer.subdata(in: 0..<Data.Index(result)))
                    } else {
                        await self.stopRunning()
                        continuation.finish()
                    }
                }
            }
        }
    }

    var performanceData: SRTPerformanceData {
        .init(mon: perf)
    }

    var status: Status {
        .init(srt_getsockstate(socket)) ?? .unknown
    }

    private(set) var isRunning = false
    private var perf: CBytePerfMon = .init()
    private var socket: SRTSOCKET = SRT_INVALID_SOCK
    private var outputs: AsyncStream<Data>.Continuation? {
        didSet {
            oldValue?.finish()
        }
    }
    private var connected: Bool {
        status == .connected
    }
    private var windowSizeC: Int32 = 1024 * 4
    private lazy var incomingBuffer: Data = .init(count: Int(windowSizeC))

    init() {
        socket = srt_create_socket()
    }

    init(socket: SRTSOCKET, options: [SRTSocketOption]) async throws {
        self.socket = socket
        guard configure(options, restriction: .post) else {
            throw makeSocketError()
        }
        if incomingBuffer.count < windowSizeC {
            incomingBuffer = .init(count: Int(windowSizeC))
        }
    }

    func getSocketOption(_ name: SRTSocketOption.Name) throws -> SRTSocketOption {
        return try SRTSocketOption(name: name, socket: socket)
    }

    func setSocketOption(_ option: SRTSocketOption) throws {
        try option.setSockflag(socket)
    }

    func open(_ url: SRTSocketURL) async throws {
        if socket == SRT_INVALID_SOCK {
            throw makeSocketError()
        }
        guard configure(url.options, restriction: .pre) else {
            throw makeSocketError()
        }
        let status: Int32 = try {
            switch url.mode {
            case .caller:
                guard let remote = url.remote else {
                    throw Error.invalidArgument("missing remote url")
                }
                return try remote.resolve(AI_ADDRCONFIG) { name, length in
                    srt_connect(socket, name, length)
                }
            case .listener:
                guard let local = url.local else {
                    throw Error.invalidArgument("missing local url")
                }
                let _: Int32 = try local.resolve(AI_PASSIVE) { name, length in
                    let status = srt_bind(socket, name, length)
                    if status == SRT_ERROR {
                        return nil
                    } else {
                        return status
                    }
                }
                return srt_listen(socket, 1)
            case .rendezvous:
                guard let remote = url.remote else {
                    throw Error.invalidArgument("missing remote url")
                }
                guard let local = url.local else {
                    throw Error.invalidArgument("missing local url")
                }
                return try remote.resolve(AI_PASSIVE | AI_ADDRCONFIG) { remotename, remotelen in
                    return try local.resolve(AI_PASSIVE | AI_ADDRCONFIG) { localname, locallen in
                        let status = srt_rendezvous(socket, localname, locallen, remotename, remotelen)
                        if status == SRT_ERROR {
                            return nil
                        } else {
                            return status
                        }
                    }
                }
            }
        }()
        guard status != SRT_ERROR else {
            let reason = SRTRejectReason(socket: socket) ?? .unknown
            throw Error.rejected(reason)
        }
        switch url.mode {
        case .listener:
            break
        default:
            guard configure(url.options, restriction: .post) else {
                throw makeSocketError()
            }
            if incomingBuffer.count < windowSizeC {
                incomingBuffer = .init(count: Int(windowSizeC))
            }
        }
        await startRunning()
    }

    func accept(_ options: [SRTSocketOption]) async throws -> SRTSocket {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<SRTSocket, Swift.Error>) in
            Task.detached { [self] in
                do {
                    let accept = srt_accept(await socket, nil, nil)
                    guard -1 < accept else {
                        throw await makeSocketError()
                    }
                    let socket = try await SRTSocket(socket: accept, options: options)
                    await socket.startRunning()
                    continuation.resume(returning: socket)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func send(_ data: Data) throws {
        guard connected else {
            throw Error.notConnected
        }
        for data in data.chunk(Self.payloadSize) {
            outputs?.yield(data)
        }
    }

    private func configure(_ options: [SRTSocketOption], restriction: SRTSocketOption.Restriction) -> Bool {
        var failures: [String] = []
        for option in options where option.name.restriction == restriction {
            do {
                try option.setSockflag(socket)
            } catch {
                failures.append(option.name.rawValue)
            }
        }
        guard failures.isEmpty else {
            logger.error(failures)
            return false
        }
        return true
    }

    private func bstats() -> Int32 {
        guard socket != SRT_INVALID_SOCK else {
            return SRT_ERROR
        }
        return srt_bstats(socket, &perf, 1)
    }

    private func makeSocketError() -> Error {
        let error_message = String(cString: srt_getlasterror_str())
        defer {
            logger.error(error_message)
        }
        if socket != SRT_INVALID_SOCK {
            srt_close(socket)
            socket = SRT_INVALID_SOCK
        }
        return .illegalState(error_message)
    }

    @inline(__always)
    private func sendmsg(_ data: Data) -> Int32 {
        return data.withUnsafeBytes { pointer in
            guard let buffer = pointer.baseAddress?.assumingMemoryBound(to: CChar.self) else {
                return SRT_ERROR
            }
            return srt_sendmsg(socket, buffer, Int32(data.count), -1, 0)
        }
    }

    @inline(__always)
    private func recvmsg() -> Int32 {
        return incomingBuffer.withUnsafeMutableBytes { pointer in
            guard let buffer = pointer.baseAddress?.assumingMemoryBound(to: CChar.self) else {
                return SRT_ERROR
            }
            return srt_recvmsg(socket, buffer, windowSizeC)
        }
    }
}

extension SRTSocket: AsyncRunner {
    // MARK: AsyncRunner
    func startRunning() async {
        guard !isRunning else {
            return
        }
        let stream = AsyncStream<Data> { continuation in
            self.outputs = continuation
        }
        Task {
            for await data in stream {
                let result = sendmsg(data)
                if result == -1 {
                    await stopRunning()
                }
            }
        }
        isRunning = true
    }

    func stopRunning() async {
        guard isRunning else {
            return
        }
        srt_close(socket)
        socket = SRT_INVALID_SOCK
        outputs = nil
        isRunning = false
    }
}

extension SRTSocket: NetworkTransportReporter {
    // MARK: NetworkTransportReporter
    func makeNetworkTransportReport() -> NetworkTransportReport {
        _ = bstats()
        let performanceData = self.performanceData
        return .init(
            queueBytesOut: Int(performanceData.byteSndBuf),
            totalBytesIn: Int(performanceData.byteRecvTotal),
            totalBytesOut: Int(performanceData.byteSentTotal)
        )
    }

    func makeNetworkMonitor() -> NetworkMonitor {
        return .init(self)
    }
}
