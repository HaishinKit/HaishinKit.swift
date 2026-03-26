import AVFoundation
import Combine
import Foundation
import HaishinKit

// MARK: -
/// The RTMPConnection class create a two-way RTMP connection.
public actor RTMPConnection: HaishinKit.NetworkConnection {
    /// The error domain code.
    public enum Error: Swift.Error {
        /// An invalid internal stare.
        case invalidState
        /// The command isn’t supported.
        case unsupportedCommand(_ command: String)
        /// The connection operation timed out.
        case connectionTimedOut
        /// The general socket error.
        case socketErrorOccurred(_ error: (any Swift.Error)?)
        /// The requested operation timed out.
        case requestTimedOut
        /// A request fails.
        case requestFailed(response: RTMPResponse)
    }

    enum ReadyState: UInt8 {
        case uninitialized
        case versionSent
        case ackSent
        case handshakeDone
    }

    /// The default time to wait for TCP/IP Handshake done.
    public static let defaultTimeout: Int = 15 // sec
    /// The default network's window size for RTMPConnection.
    public static let defaultWindowSizeS: Int64 = 250000
    /// The supported protocols are rtmp, rtmps, rtmpt and rtmps.
    public static let supportedProtocols: Set<String> = ["rtmp", "rtmps"]
    /// The supported fourCcList.
    public static let supportedFourCcList = [RTMPVideoFourCC.hevc.description, RTMPAudioFourCC.opus.description]
    /// The default RTMP port is 1935.
    public static let defaultPort: Int = 1935
    /// The default RTMPS port is 443.
    public static let defaultSecurePort: Int = 443
    /// The default flashVer is FMLE/3.0 (compatible; FMSc/1.0).
    public static let defaultFlashVer: String = "FMLE/3.0 (compatible; FMSc/1.0)"
    /// The default chunk size for RTMPConnection.
    public static let defaultChunkSizeS: Int = 1024 * 8
    /// The default capabilities for RTMPConnection.
    public static let defaultCapabilities: Int = 239
    /// The default object encoding for RTMPConnection class.
    public static let defaultObjectEncoding: RTMPObjectEncoding = .amf0
    /// The default an rtmp request time out value (ms).
    public static let defaultRequestTimeout: UInt64 = 3000
    /// The supported audio fourCc Information.
    public static let supportedAudioFourCcInfoMap: AMFObject = [
        RTMPAudioFourCC.opus.description: FourCcInfoMask.canEncode.rawValue
    ]
    /// The supported video fourCc Information.
    public static let supportedVideoFourCcInfoMap: AMFObject = [
        RTMPVideoFourCC.hevc.description: FourCcInfoMask.canDecode.rawValue | FourCcInfoMask.canEncode.rawValue
    ]
    private static let connectTransactionId = 1

    /**
     - NetStatusEvent#info.code for NetConnection
     - see: https://help.adobe.com/en_US/air/reference/html/flash/events/NetStatusEvent.html#NET_STATUS
     */
    public enum Code: String {
        case callBadVersion       = "NetConnection.Call.BadVersion"
        case callFailed           = "NetConnection.Call.Failed"
        case callProhibited       = "NetConnection.Call.Prohibited"
        case connectAppshutdown   = "NetConnection.Connect.AppShutdown"
        case connectClosed        = "NetConnection.Connect.Closed"
        case connectFailed        = "NetConnection.Connect.Failed"
        case connectIdleTimeOut   = "NetConnection.Connect.IdleTimeOut"
        case connectInvalidApp    = "NetConnection.Connect.InvalidApp"
        case connectNetworkChange = "NetConnection.Connect.NetworkChange"
        case connectRejected      = "NetConnection.Connect.Rejected"
        case connectSuccess       = "NetConnection.Connect.Success"

        public var level: String {
            switch self {
            case .callBadVersion:
                return "error"
            case .callFailed:
                return "error"
            case .callProhibited:
                return "error"
            case .connectAppshutdown:
                return "error"
            case .connectClosed:
                return "status"
            case .connectFailed:
                return "error"
            case .connectIdleTimeOut:
                return "status"
            case .connectInvalidApp:
                return "error"
            case .connectNetworkChange:
                return "status"
            case .connectRejected:
                return "error"
            case .connectSuccess:
                return "status"
            }
        }

        func status(_ description: String) -> RTMPStatus {
            return .init(code: rawValue, level: level, description: description)
        }
    }

    enum SupportVideo: UInt16 {
        case unused = 0x0001
        case jpeg = 0x0002
        case sorenson = 0x0004
        case homebrew = 0x0008
        case vp6 = 0x0010
        case vp6Alpha = 0x0020
        case homebrewv = 0x0040
        case h264 = 0x0080
        case all = 0x00FF
    }

    enum SupportSound: UInt16 {
        case none = 0x0001
        case adpcm = 0x0002
        case mp3 = 0x0004
        case intel = 0x0008
        case unused = 0x0010
        case nelly8 = 0x0020
        case nelly = 0x0040
        case g711A = 0x0080
        case g711U = 0x0100
        case nelly16 = 0x0200
        case aac = 0x0400
        case speex = 0x0800
        case all = 0x0FFF
    }

    enum VideoFunction: UInt8 {
        case clientSeek = 1
    }

    enum FourCcInfoMask: Int {
        case canDecode = 0x01
        case canEncode = 0x02
        case canForward = 0x04
    }

    enum CapsEx: Int {
        case recoonect = 0x01
        case multitrack = 0x02
        case modEx = 0x04
        case timestampNanoOffset = 0x08
    }

    /// The URL of .swf.
    public let swfUrl: String?
    /// The URL of an HTTP referer.
    public let pageUrl: String?
    /// The name of application.
    public let flashVer: String
    /// The fourCcList for Enhancing NetConnection connect Command.
    public let fourCcList: [String]?
    /// The audio fourCc information for Enhancing NetConnection connect Command.
    public let audioFourCcInfoMap: AMFObject?
    /// The video fourCc information for Enhancing NetConnection connect Command.
    public let videoFourCcInfoMap: AMFObject?
    /// The capability flags for Enhancing NetConnection connect Command.
    public let capsEx: Int
    /// The time to wait for TCP/IP Handshake done.
    public let timeout: Int
    /// The RTMP request timeout value. Defaul value is 500 msec.
    public let requestTimeout: UInt64
    /// The outgoing RTMPChunkSize.
    public let chunkSize: Int
    /// The dispatchQos for socket.
    public let qualityOfService: DispatchQoS
    /// The URI passed to the Self.connect() method.
    public private(set) var uri: URL?
    /// The instance connected to server(true) or not(false).
    @Published public private(set) var connected = false
    /// The stream of events you receive RTMP status events from a service.
    public var status: AsyncStream<RTMPStatus> {
        AsyncStream { continuation in
            statusContinuation = continuation
        }
    }
    /// The object encoding for this RTMPConnection instance.
    public let objectEncoding = RTMPConnection.defaultObjectEncoding

    var newTransaction: Int {
        currentTransactionId += 1
        return currentTransactionId
    }

    private var socket: RTMPSocket?
    private var chunks: [UInt16: RTMPChunkMessageHeader] = [:]
    private var streams: [RTMPStream] = []
    private var sequence: Int64 = 0
    private var bandWidth: UInt32 = 0
    private var handshake: RTMPHandshake = .init()
    private var arguments: [(any Sendable)?] = []
    private var readyState: ReadyState = .uninitialized {
        didSet {
            logger.info(oldValue, "=>", readyState)
        }
    }
    private var chunkSizeC = RTMPChunkMessageHeader.chunkSize {
        didSet {
            guard chunkSizeC != oldValue else {
                return
            }
            inputBuffer.chunkSize = chunkSizeC
        }
    }
    private var chunkSizeS = RTMPChunkMessageHeader.chunkSize {
        didSet {
            guard chunkSizeS != oldValue else {
                return
            }
            outputBuffer.chunkSize = chunkSizeS
        }
    }
    private var operations: [Int: CheckedContinuation<RTMPResponse, any Swift.Error>] = [:]
    private var inputBuffer = RTMPChunkBuffer()
    private var windowSizeC = RTMPConnection.defaultWindowSizeS {
        didSet {
            guard connected else {
                return
            }
            doOutput(.zero, chunkStreamId: .control, message: RTMPWindowAcknowledgementSizeMessage(size: UInt32(windowSizeC)))
        }
    }
    private var windowSizeS = RTMPConnection.defaultWindowSizeS
    private var outputBuffer = RTMPChunkBuffer()
    private let authenticator = RTMPAuthenticator()
    private var networkMonitor: NetworkMonitor?
    private var statusContinuation: AsyncStream<RTMPStatus>.Continuation?
    private var currentTransactionId = RTMPConnection.connectTransactionId

    /// Creates a new connection with E-RTMP command parameters.
    ///
    /// You can specify the fourCcList parameter of the connect command defined in E-RTMP.
    /// In some RTMP server implementations where these parameters are not supported, you can work around the issue by specifying them as shown below.
    ///
    /// ## Example code:
    /// ```swift
    /// let connection = RTMPConnection(
    ///  fourCcList: nil,
    ///  videoFourCcInfoMap: nil,
    ///  audioFourCcInfoMap: nil,
    ///  capsEx: 0
    /// )
    /// ```
    public init(
        swfUrl: String? = nil,
        pageUrl: String? = nil,
        flashVer: String = RTMPConnection.defaultFlashVer,
        fourCcList: [String]? = RTMPConnection.supportedFourCcList,
        videoFourCcInfoMap: AMFObject? = RTMPConnection.supportedVideoFourCcInfoMap,
        audioFourCcInfoMap: AMFObject? = RTMPConnection.supportedAudioFourCcInfoMap,
        capsEx: Int = 0,
        timeout: Int = RTMPConnection.defaultTimeout,
        requestTimeout: UInt64 = RTMPConnection.defaultRequestTimeout,
        chunkSize: Int = RTMPConnection.defaultChunkSizeS,
        qualityOfService: DispatchQoS = .userInitiated) {
        self.swfUrl = swfUrl
        self.pageUrl = pageUrl
        self.flashVer = flashVer
        self.timeout = timeout
        self.fourCcList = fourCcList
        self.videoFourCcInfoMap = videoFourCcInfoMap
        self.audioFourCcInfoMap = audioFourCcInfoMap
        self.capsEx = capsEx
        self.requestTimeout = requestTimeout
        self.chunkSize = chunkSize
        self.qualityOfService = qualityOfService
    }

    deinit {
        streams.removeAll()
    }

    /// Calls a command or method on RTMP Server.
    public func call(_ commandName: String, arguments: (any Sendable)?...) async throws -> RTMPResponse {
        guard connected else {
            throw Error.invalidState
        }
        return try await withCheckedThrowingContinuation { continutation in
            let message = RTMPCommandMessage(
                streamId: 0,
                transactionId: newTransaction,
                objectEncoding: objectEncoding,
                commandName: commandName,
                commandObject: nil,
                arguments: arguments
            )
            Task {
                try? await Task.sleep(nanoseconds: requestTimeout * 1_000_000)
                guard let operation = operations.removeValue(forKey: message.transactionId) else {
                    return
                }
                operation.resume(throwing: Error.requestTimedOut)
            }
            operations[message.transactionId] = continutation
            doOutput(.zero, chunkStreamId: .command, message: message)
        }
    }

    /// Creates a two-way connection to an application on RTMP Server.
    public func connect(_ command: String, arguments: (any Sendable)?...) async throws -> RTMPResponse {
        guard !connected else {
            throw Error.invalidState
        }
        guard let uri = URL(string: command), let scheme = uri.scheme, let host = uri.host, Self.supportedProtocols.contains(scheme) else {
            throw Error.unsupportedCommand(command)
        }
        self.uri = uri
        self.arguments = arguments
        let secure = uri.scheme == "rtmps" || uri.scheme == "rtmpts"
        handshake.clear()
        chunks.removeAll()
        sequence = 0
        readyState = .uninitialized
        chunkSizeC = RTMPChunkMessageHeader.chunkSize
        chunkSizeS = RTMPChunkMessageHeader.chunkSize
        currentTransactionId = Self.connectTransactionId
        socket = RTMPSocket(qualityOfService: qualityOfService, securityLevel: secure ? .negotiatedSSL : .none)
        networkMonitor = await socket?.makeNetworkMonitor()
        guard let socket, let networkMonitor else {
            throw Error.invalidState
        }
        do {
            let result: RTMPResponse = try await withCheckedThrowingContinuation { continutation in
                Task {
                    do {
                        try await socket.connect(host, port: uri.port ?? (secure ? Self.defaultSecurePort : Self.defaultPort))
                    } catch {
                        continutation.resume(throwing: error)
                        return
                    }
                    do {
                        readyState = .versionSent
                        await socket.send(handshake.c0c1packet)
                        operations[Self.connectTransactionId] = continutation
                        for await data in await socket.recv() {
                            try await listen(data)
                        }
                        try? await close()
                    } catch {
                        try? await close()
                    }
                }
            }
            Task {
                for await event in await networkMonitor.event {
                    dispatch(event)
                }
            }
            for stream in streams {
                await stream.dispatch(.reset)
                await stream.createStream()
            }
            return result
        } catch let error as RTMPSocket.Error {
            switch error {
            case .connectionTimedOut:
                throw Error.connectionTimedOut
            case .connectionNotEstablished(let socketError):
                throw Error.socketErrorOccurred(socketError)
            default:
                throw Error.socketErrorOccurred(nil)
            }
        } catch let error as Error {
            switch error {
            case .requestFailed(let response):
                guard let status = response.status else {
                    throw error
                }
                // Handles an RTMP auth.
                if status.code == RTMPConnection.Code.connectRejected.rawValue {
                    switch authenticator.makeCommand(command, status: status) {
                    case .success(let command):
                        await socket.close()
                        return try await connect(command, arguments: arguments)
                    case .failure:
                        throw error
                    }
                } else {
                    throw error
                }
            default:
                throw error
            }
        } catch {
            throw error
        }
    }

    /// Closes the connection from the server.
    public func close() async throws {
        guard readyState != .uninitialized else {
            throw Error.invalidState
        }

        uri = nil
        for stream in streams {
            if await stream.fcPublishName == nil {
                _ = try? await stream.close()
            } else {
                await stream.deleteStream()
            }
        }
        await socket?.close()
        await networkMonitor?.stopRunning()

        let status = readyState == .handshakeDone ?
            Code.connectClosed.status("") :
            Code.connectFailed.status("")

        connected = false
        readyState = .uninitialized

        if let operation = operations.removeValue(forKey: Self.connectTransactionId) {
            operation.resume(throwing: Error.requestFailed(response: .init(status: status)))
        } else {
            statusContinuation?.yield(status)
        }
    }

    @discardableResult
    func doOutput(_ type: RTMPChunkType, chunkStreamId: RTMPChunkStreamId, message: some RTMPMessage) -> Int {
        if logger.isEnabledFor(level: .trace) {
            logger.trace("<<", message)
        }
        let chunks = Array(outputBuffer.putMessage(type, chunkStreamId: chunkStreamId.rawValue, message: message))
        Task {
            await socket?.send(chunks)
        }
        return message.payload.count
    }

    func addStream(_ stream: RTMPStream) {
        streams.append(stream)
    }

    private func listen(_ data: Data) async throws {
        switch readyState {
        case .versionSent:
            handshake.put(data)
            guard handshake.hasS0S1Packet else {
                return
            }
            await socket?.send(handshake.c2packet())
            readyState = .ackSent
            try await listen(.init())
        case .ackSent:
            handshake.put(data)
            guard handshake.hasS2Packet else {
                return
            }
            readyState = .handshakeDone
            guard let message = makeConnectionMessage() else {
                try await close()
                break
            }
            await networkMonitor?.startRunning()
            doOutput(.zero, chunkStreamId: .command, message: message)
        case .handshakeDone:
            inputBuffer.put(data)
            var rollbackPosition = inputBuffer.position
            do {
                while inputBuffer.hasRemaining {
                    rollbackPosition = inputBuffer.position
                    let (chunkType, chunkStreamId) = try inputBuffer.getBasicHeader()
                    if chunks[chunkStreamId] == nil {
                        chunks[chunkStreamId] = RTMPChunkMessageHeader()
                    }
                    if let messageHeader = chunks[chunkStreamId] {
                        try inputBuffer.getMessageHeader(chunkType, messageHeader: messageHeader)
                        if let message = messageHeader.makeMessage() {
                            await dispatch(message, type: chunkType)
                            messageHeader.reset()
                        }
                    }
                }
            } catch RTMPChunkError.unknowChunkType(let value) {
                logger.error("Received unknow chunk type =", value)
                try await close()
            } catch RTMPChunkError.bufferUnderflow {
                inputBuffer.position = rollbackPosition
            }
        default:
            break
        }
    }

    private func dispatch(_ event: NetworkMonitorEvent) {
        switch event {
        case .status(let report), .publishInsufficientBWOccured(let report):
            if windowSizeS * (sequence + 1) <= report.totalBytesIn {
                doOutput(sequence == 0 ? .zero : .one, chunkStreamId: .control, message: RTMPAcknowledgementMessage(sequence: UInt32(report.totalBytesIn)))
                sequence += 1
            }
        case .reset:
            // noop
            break
        }
        for stream in streams {
            Task { await stream.dispatch(event) }
        }
    }

    private func dispatch(_ message: some RTMPMessage, type: RTMPChunkType) async {
        if logger.isEnabledFor(level: .trace) {
            logger.trace(">>", message)
        }
        if message.streamId == 0 {
            switch message {
            case let message as RTMPSetChunkSizeMessage:
                chunkSizeC = Int(message.size)
            case let message as RTMPWindowAcknowledgementSizeMessage:
                windowSizeC = Int64(message.size)
                windowSizeS = Int64(message.size)
            case let message as RTMPSetPeerBandwidthMessage:
                bandWidth = message.size
            case let message as RTMPCommandMessage:
                let response = RTMPResponse(message)
                defer {
                    if let status = response.status {
                        statusContinuation?.yield(status)
                    }
                }
                guard let responder = operations.removeValue(forKey: message.transactionId) else {
                    switch message.commandName {
                    case "close":
                        try? await close()
                    default:
                        break
                    }
                    return
                }
                switch message.commandName {
                case "_result":
                    if message.transactionId == Self.connectTransactionId {
                        connected = true
                        chunkSizeS = chunkSize
                        doOutput(.zero, chunkStreamId: .control, message: RTMPSetChunkSizeMessage(size: UInt32(chunkSizeS)))
                    }
                    responder.resume(returning: response)
                default:
                    responder.resume(throwing: Error.requestFailed(response: response))
                }
            case let message as RTMPSharedObjectMessage:
                guard let remotePath = uri?.absoluteWithoutQueryString else {
                    return
                }
                let persistence = (message.flags[3] & 2) != 0
                await RTMPSharedObject.getRemote(withName: message.sharedObjectName, remotePath: remotePath, persistence: persistence).on(message: message)
            case let message as RTMPUserControlMessage:
                switch message.event {
                case .ping:
                    doOutput(.zero, chunkStreamId: .control, message: RTMPUserControlMessage(event: .pong, value: message.value))
                default:
                    for stream in streams where await stream.id == message.value {
                        Task { await stream.dispatch(message, type: type) }
                    }
                }
            default:
                break
            }
        } else {
            for stream in streams where await stream.id == message.streamId {
                Task { await stream.dispatch(message, type: type) }
            }
        }
    }

    private func makeConnectionMessage() -> RTMPCommandMessage? {
        guard let uri else {
            return nil
        }
        var app = uri.path.isEmpty ? "" : String(uri.path[uri.path.index(uri.path.startIndex, offsetBy: 1)...])
        if let query = uri.query {
            app += "?" + query
        }
        return RTMPCommandMessage(
            streamId: 0,
            transactionId: Self.connectTransactionId,
            // "connect" must be a objectEncoding = 0
            objectEncoding: .amf0,
            commandName: "connect",
            commandObject: [
                "objectEncoding": objectEncoding.rawValue,
                "app": app,
                "flashVer": flashVer,
                "swfUrl": swfUrl,
                "tcUrl": uri.absoluteWithoutAuthenticationString,
                "fpad": false,
                "capabilities": Self.defaultCapabilities,
                "audioCodecs": SupportSound.aac.rawValue,
                "videoCodecs": SupportVideo.h264.rawValue,
                "videoFunction": VideoFunction.clientSeek.rawValue,
                "pageUrl": pageUrl,
                // Enhancing NetConnection connect Command
                "fourCcList": fourCcList,
                "videoFourCcInfoMap": videoFourCcInfoMap,
                "audioFourCcInfoMap": audioFourCcInfoMap,
                "capsEx": capsEx
            ],
            arguments: arguments
        )
    }
}
