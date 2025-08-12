import Foundation
import HaishinKit
import libsrt
import Logboard

private let kSRTSOcket_payloadSize: Int = 1316

protocol SRTSocketDelegate: AnyObject {
    func socket(_ socket: SRTSocket<Self>, status: SRT_SOCKSTATUS)
    func socket(_ socket: SRTSocket<Self>, incomingDataAvailabled data: Data, bytes: Int32)
    func socket(_ socket: SRTSocket<Self>, didAcceptSocket client: SRTSocket<Self>)
}

final class SRTSocket<T: SRTSocketDelegate> {
    var timeout: Int = 0
    var options: [SRTSocketOption: Any] = [:]
    weak var delegate: T?
    private(set) var mode: SRTMode = .caller
    private(set) var perf: CBytePerfMon = .init()
    private(set) var isRunning: Atomic<Bool> = .init(false)
    private(set) var socket: SRTSOCKET = SRT_INVALID_SOCK
    private(set) var status: SRT_SOCKSTATUS = SRTS_INIT {
        didSet {
            guard status != oldValue else {
                return
            }
            switch status {
            case SRTS_INIT: // 1
                logger.trace("SRT Socket Init")
            case SRTS_OPENED:
                logger.info("SRT Socket opened")
            case SRTS_LISTENING:
                logger.trace("SRT Socket Listening")
            case SRTS_CONNECTING:
                logger.trace("SRT Socket Connecting")
            case SRTS_CONNECTED:
                logger.info("SRT Socket Connected")
            case SRTS_BROKEN:
                logger.warn("SRT Socket Broken")
                close()
            case SRTS_CLOSING:
                logger.trace("SRT Socket Closing")
            case SRTS_CLOSED:
                logger.info("SRT Socket Closed")
                stopRunning()
            case SRTS_NONEXIST:
                logger.warn("SRT Socket Not Exist")
            default:
                break
            }
            delegate?.socket(self, status: status)
        }
    }
    private var windowSizeC: Int32 = 1024 * 4
    private var outgoingBuffer: [Data] = .init()
    private lazy var incomingBuffer: Data = .init(count: Int(windowSizeC))
    private let outgoingQueue: DispatchQueue = .init(label: "com.haishinkit.SRTHaishinKit.SRTSocket.outgoing", qos: .userInitiated)
    private let incomingQueue: DispatchQueue = .init(label: "com.haishinkit.SRTHaishinKit.SRTSocket.incoming", qos: .userInitiated)

    init() {
    }

    init(socket: SRTSOCKET) throws {
        self.socket = socket
        guard configure(.post) else {
            throw makeSocketError()
        }
        if incomingBuffer.count < windowSizeC {
            incomingBuffer = .init(count: Int(windowSizeC))
        }
    }

    func open(_ addr: sockaddr_in, mode: SRTMode, options: [SRTSocketOption: Any] = [:]) throws {
        guard socket == SRT_INVALID_SOCK else {
            return
        }
        self.mode = mode
        // prepare socket
        socket = srt_create_socket()
        if socket == SRT_INVALID_SOCK {
            throw makeSocketError()
        }
        self.options = options
        guard configure(.pre) else {
            throw makeSocketError()
        }
        // prepare connect
        var addr_cp = addr
        var stat = withUnsafePointer(to: &addr_cp) { ptr -> Int32 in
            let psa = UnsafeRawPointer(ptr).assumingMemoryBound(to: sockaddr.self)
            return mode.open(socket, psa, Int32(MemoryLayout.size(ofValue: addr)))
        }
        if stat == SRT_ERROR {
            throw makeSocketError()
        }
        switch mode {
        case .caller:
            guard configure(.post) else {
                throw makeSocketError()
            }
            if incomingBuffer.count < windowSizeC {
                incomingBuffer = .init(count: Int(windowSizeC))
            }
        case .listener:
            // only supporting a single connection
            stat = srt_listen(socket, 1)
            if stat == SRT_ERROR {
                srt_close(socket)
                throw makeSocketError()
            }
        }
        startRunning()
    }

    func close() {
        guard socket != SRT_INVALID_SOCK else {
            return
        }
        srt_close(socket)
        socket = SRT_INVALID_SOCK
        stopRunning()
    }

    func doOutput(data: Data) {
        outgoingQueue.async {
            self.outgoingBuffer.append(contentsOf: data.chunk(kSRTSOcket_payloadSize))
            repeat {
                guard var data = self.outgoingBuffer.first else {
                    return
                }
                _ = self.sendmsg2(&data)
                self.outgoingBuffer.remove(at: 0)
            } while !self.outgoingBuffer.isEmpty
        }
    }

    func doInput() {
        switch mode {
        case .caller:
            incomingQueue.async {
                repeat {
                    let result = self.recvmsg()
                    if 0 < result {
                        self.delegate?.socket(self, incomingDataAvailabled: self.incomingBuffer, bytes: result)
                    }
                } while self.isRunning.value
            }
        case .listener:
            break
        }
    }

    func configure(_ binding: SRTSocketOption.Binding) -> Bool {
        let failures = SRTSocketOption.configure(socket, binding: binding, options: options)
        guard failures.isEmpty else {
            logger.error(failures)
            return false
        }
        return true
    }

    func bstats() -> Int32 {
        guard socket != SRT_INVALID_SOCK else {
            return SRT_ERROR
        }
        return srt_bstats(socket, &perf, 1)
    }

    func reject() {
        srt_setrejectreason(socket, Int32(SRT_REJ_CLOSE.rawValue))
        srt_close(socket)
    }

    private func accept() {
        let socket = srt_accept(socket, nil, nil)
        do {
            delegate?.socket(self, didAcceptSocket: try SRTSocket(socket: socket))
        } catch {
            logger.error(error)
        }
    }

    private func makeSocketError() -> SRTError {
        let error_message = String(cString: srt_getlasterror_str())
        logger.error(error_message)
        return SRTError.illegalState(message: error_message)
    }

    @inline(__always)
    private func sendmsg2(_ data: inout Data) -> Int32 {
        return data.withUnsafeBytes { pointer in
            guard let buffer = pointer.baseAddress?.assumingMemoryBound(to: CChar.self) else {
                return SRT_ERROR
            }
            return srt_sendmsg2(socket, buffer, Int32(data.count), nil)
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

extension SRTSocket: Running {
    // MARK: Running
    func startRunning() {
        guard !isRunning.value else {
            return
        }
        isRunning.mutate { $0 = true }
        DispatchQueue(label: "com.haishkinkit.SRTHaishinKit.SRTSocket.runloop").async {
            repeat {
                self.status = srt_getsockstate(self.socket)
                switch self.mode {
                case .listener:
                    self.accept()
                default:
                    break
                }
                usleep(3 * 10000)
            } while self.isRunning.value
        }
    }

    func stopRunning() {
        guard isRunning.value else {
            return
        }
        isRunning.mutate { $0 = false }
    }
}
