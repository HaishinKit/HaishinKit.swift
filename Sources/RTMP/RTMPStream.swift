import AVFoundation

/// An object that provides the interface to control a one-way channel over a RtmpConnection.
open class RTMPStream: IOStream {
    /// NetStatusEvent#info.code for NetStream
    /// - seealso: https://help.adobe.com/en_US/air/reference/html/flash/events/NetStatusEvent.html#NET_STATUS
    public enum Code: String {
        case bufferEmpty               = "NetStream.Buffer.Empty"
        case bufferFlush               = "NetStream.Buffer.Flush"
        case bufferFull                = "NetStream.Buffer.Full"
        case connectClosed             = "NetStream.Connect.Closed"
        case connectFailed             = "NetStream.Connect.Failed"
        case connectRejected           = "NetStream.Connect.Rejected"
        case connectSuccess            = "NetStream.Connect.Success"
        case drmUpdateNeeded           = "NetStream.DRM.UpdateNeeded"
        case failed                    = "NetStream.Failed"
        case multicastStreamReset      = "NetStream.MulticastStream.Reset"
        case pauseNotify               = "NetStream.Pause.Notify"
        case playFailed                = "NetStream.Play.Failed"
        case playFileStructureInvalid  = "NetStream.Play.FileStructureInvalid"
        case playInsufficientBW        = "NetStream.Play.InsufficientBW"
        case playNoSupportedTrackFound = "NetStream.Play.NoSupportedTrackFound"
        case playReset                 = "NetStream.Play.Reset"
        case playStart                 = "NetStream.Play.Start"
        case playStop                  = "NetStream.Play.Stop"
        case playStreamNotFound        = "NetStream.Play.StreamNotFound"
        case playTransition            = "NetStream.Play.Transition"
        case playUnpublishNotify       = "NetStream.Play.UnpublishNotify"
        case publishBadName            = "NetStream.Publish.BadName"
        case publishIdle               = "NetStream.Publish.Idle"
        case publishStart              = "NetStream.Publish.Start"
        case recordAlreadyExists       = "NetStream.Record.AlreadyExists"
        case recordFailed              = "NetStream.Record.Failed"
        case recordNoAccess            = "NetStream.Record.NoAccess"
        case recordStart               = "NetStream.Record.Start"
        case recordStop                = "NetStream.Record.Stop"
        case recordDiskQuotaExceeded   = "NetStream.Record.DiskQuotaExceeded"
        case secondScreenStart         = "NetStream.SecondScreen.Start"
        case secondScreenStop          = "NetStream.SecondScreen.Stop"
        case seekFailed                = "NetStream.Seek.Failed"
        case seekInvalidTime           = "NetStream.Seek.InvalidTime"
        case seekNotify                = "NetStream.Seek.Notify"
        case stepNotify                = "NetStream.Step.Notify"
        case unpauseNotify             = "NetStream.Unpause.Notify"
        case unpublishSuccess          = "NetStream.Unpublish.Success"
        case videoDimensionChange      = "NetStream.Video.DimensionChange"

        public var level: String {
            switch self {
            case .bufferEmpty:
                return "status"
            case .bufferFlush:
                return "status"
            case .bufferFull:
                return "status"
            case .connectClosed:
                return "status"
            case .connectFailed:
                return "error"
            case .connectRejected:
                return "error"
            case .connectSuccess:
                return "status"
            case .drmUpdateNeeded:
                return "status"
            case .failed:
                return "error"
            case .multicastStreamReset:
                return "status"
            case .pauseNotify:
                return "status"
            case .playFailed:
                return "error"
            case .playFileStructureInvalid:
                return "error"
            case .playInsufficientBW:
                return "warning"
            case .playNoSupportedTrackFound:
                return "status"
            case .playReset:
                return "status"
            case .playStart:
                return "status"
            case .playStop:
                return "status"
            case .playStreamNotFound:
                return "error"
            case .playTransition:
                return "status"
            case .playUnpublishNotify:
                return "status"
            case .publishBadName:
                return "error"
            case .publishIdle:
                return "status"
            case .publishStart:
                return "status"
            case .recordAlreadyExists:
                return "status"
            case .recordFailed:
                return "error"
            case .recordNoAccess:
                return "error"
            case .recordStart:
                return "status"
            case .recordStop:
                return "status"
            case .recordDiskQuotaExceeded:
                return "error"
            case .secondScreenStart:
                return "status"
            case .secondScreenStop:
                return "status"
            case .seekFailed:
                return "error"
            case .seekInvalidTime:
                return "error"
            case .seekNotify:
                return "status"
            case .stepNotify:
                return "status"
            case .unpauseNotify:
                return "status"
            case .unpublishSuccess:
                return "status"
            case .videoDimensionChange:
                return "status"
            }
        }

        func data(_ description: String) -> ASObject {
            [
                "code": rawValue,
                "level": level,
                "description": description
            ]
        }
    }

    /// The type of publish options.
    public enum HowToPublish: String, Sendable {
        /// Publish with server-side recording.
        case record
        /// Publish with server-side recording which is to append file if exists.
        case append
        /// Publish with server-side recording which is to append and ajust time file if exists.
        case appendWithGap
        /// Publish.
        case live
    }

    private struct PausedStatus {
        let audioIsMuted: Bool
        let videoIsMuted: Bool

        init(_ stream: IOStream) {
            audioIsMuted = stream.audioMixerSettings.isMuted
            videoIsMuted = stream.videoMixerSettings.isMuted
        }

        func restore(_ stream: IOStream) {
            stream.audioMixerSettings.isMuted = audioIsMuted
            stream.videoMixerSettings.isMuted = videoIsMuted
        }
    }

    static let defaultID: UInt32 = 0
    /// The RTMPStream metadata.
    public private(set) var metadata: [String: Any?] = [:]
    /// The RTMPStreamInfo object whose properties contain data.
    public internal(set) var info = RTMPStreamInfo()
    /// The object encoding (AMF). Framework supports AMF0 only.
    public private(set) var objectEncoding: RTMPObjectEncoding = RTMPConnection.defaultObjectEncoding
    /// Incoming audio plays on the stream or not.
    public var receiveAudio = true {
        didSet {
            lockQueue.async {
                guard self.readyState == .playing else {
                    return
                }
                self.connection?.doOutput(chunk: RTMPChunk(message: RTMPCommandMessage(
                    streamId: self.id,
                    transactionId: 0,
                    objectEncoding: self.objectEncoding,
                    commandName: "receiveAudio",
                    commandObject: nil,
                    arguments: [self.receiveAudio]
                )))
            }
        }
    }
    /// Incoming video plays on the stream or not.
    public var receiveVideo = true {
        didSet {
            lockQueue.async {
                guard self.readyState == .playing else {
                    return
                }
                self.connection?.doOutput(chunk: RTMPChunk(message: RTMPCommandMessage(
                    streamId: self.id,
                    transactionId: 0,
                    objectEncoding: self.objectEncoding,
                    commandName: "receiveVideo",
                    commandObject: nil,
                    arguments: [self.receiveVideo]
                )))
            }
        }
    }
    /// Pauses playback or publish of a video stream or not.
    public var paused = false {
        didSet {
            lockQueue.async {
                switch self.readyState {
                case .publish, .publishing:
                    if self.paused {
                        self.pausedStatus = .init(self)
                        self.audioMixerSettings.isMuted = true
                        self.videoMixerSettings.isMuted = true
                    } else {
                        self.pausedStatus.restore(self)
                    }
                case .play, .playing:
                    self.connection?.doOutput(chunk: RTMPChunk(message: RTMPCommandMessage(
                        streamId: self.id,
                        transactionId: 0,
                        objectEncoding: self.objectEncoding,
                        commandName: "pause",
                        commandObject: nil,
                        arguments: [self.paused, floor(self.startedAt.timeIntervalSinceNow * -1000)]
                    )))
                default:
                    break
                }
            }
        }
    }
    /// Specifies the stream name used for FMLE-compatible sequences.
    public var fcPublishName: String?

    var id: UInt32 = RTMPStream.defaultID
    var frameCount: UInt16 = 0
    private(set) lazy var muxer = {
        return RTMPMuxer(self)
    }()
    private var messages: [RTMPCommandMessage] = []
    private var startedAt = Date() {
        didSet {
            dataTimestamps.removeAll()
        }
    }
    private lazy var dispatcher: EventDispatcher = {
        EventDispatcher(target: self)
    }()
    private lazy var pausedStatus = PausedStatus(self)
    private var howToPublish: RTMPStream.HowToPublish = .live
    private var dataTimestamps: [String: Date] = .init()
    private weak var connection: RTMPConnection?

    /// Creates a new stream.
    public init(connection: RTMPConnection, fcPublishName: String? = nil) {
        self.connection = connection
        super.init()
        self.fcPublishName = fcPublishName
        connection.addStream(self)
        addEventListener(.rtmpStatus, selector: #selector(on(status:)), observer: self)
        connection.addEventListener(.rtmpStatus, selector: #selector(on(status:)), observer: self)
        if connection.connected {
            connection.createStream(self)
        }
        mixer.muxer = muxer
    }

    deinit {
        mixer.stopRunning()
        removeEventListener(.rtmpStatus, selector: #selector(on(status:)), observer: self)
        connection?.removeEventListener(.rtmpStatus, selector: #selector(on(status:)), observer: self)
    }

    /// Plays a live stream from RTMPServer.
    public func play(_ arguments: Any?...) {
        // swiftlint:disable:next closure_body_length
        lockQueue.async {
            guard let name: String = arguments.first as? String else {
                switch self.readyState {
                case .play, .playing:
                    self.info.resourceName = nil
                    self.close(withLockQueue: false)
                default:
                    break
                }
                return
            }

            self.info.resourceName = name
            let message = RTMPCommandMessage(
                streamId: self.id,
                transactionId: 0,
                objectEncoding: self.objectEncoding,
                commandName: "play",
                commandObject: nil,
                arguments: arguments
            )

            switch self.readyState {
            case .initialized:
                self.messages.append(message)
            default:
                self.readyState = .play
                self.connection?.doOutput(chunk: RTMPChunk(message: message))
            }
        }
    }

    /// Seeks the keyframe.
    public func seek(_ offset: Double) {
        lockQueue.async {
            guard self.readyState == .playing else {
                return
            }
            self.connection?.doOutput(chunk: RTMPChunk(message: RTMPCommandMessage(
                streamId: self.id,
                transactionId: 0,
                objectEncoding: self.objectEncoding,
                commandName: "seek",
                commandObject: nil,
                arguments: [offset]
            )))
        }
    }

    /// Sends streaming audio, vidoe and data message from client.
    public func publish(_ name: String?, type: RTMPStream.HowToPublish = .live) {
        // swiftlint:disable:next closure_body_length
        lockQueue.async {
            guard let name: String = name else {
                switch self.readyState {
                case .publish, .publishing:
                    self.close(withLockQueue: false)
                default:
                    break
                }
                return
            }

            if self.info.resourceName == name && self.readyState == .publishing(muxer: self.muxer) {
                self.howToPublish = type
                return
            }

            self.info.resourceName = name
            self.howToPublish = type

            let message = RTMPCommandMessage(
                streamId: self.id,
                transactionId: 0,
                objectEncoding: self.objectEncoding,
                commandName: "publish",
                commandObject: nil,
                arguments: [name, type.rawValue]
            )

            switch self.readyState {
            case .initialized:
                self.messages.append(message)
            default:
                self.readyState = .publish
                self.connection?.doOutput(chunk: RTMPChunk(message: message))
            }
        }
    }

    /// Stops playing or publishing and makes available other uses.
    public func close() {
        close(withLockQueue: true)
    }

    /// Sends a message on a published stream to all subscribing clients.
    ///
    /// ```
    /// // To add a metadata to a live stream sent to an RTMP Service.
    /// stream.send("@setDataFrame", "onMetaData", metaData)
    /// // To clear a metadata that has already been set in the stream.
    /// stream.send("@clearDataFrame", "onMetaData");
    /// ```
    ///
    /// - Parameters:
    ///   - handlerName: The message to send.
    ///   - arguemnts: Optional arguments.
    ///   - isResetTimestamp: A workaround option for sending timestamps as 0 in some services.
    public func send(handlerName: String, arguments: Any?..., isResetTimestamp: Bool = false) {
        lockQueue.async {
            guard self.readyState == .publishing(muxer: self.muxer) else {
                return
            }
            if isResetTimestamp {
                self.dataTimestamps[handlerName] = nil
            }
            let dataWasSent = self.dataTimestamps[handlerName] == nil ? false : true
            let timestmap: UInt32 = dataWasSent ? UInt32((self.dataTimestamps[handlerName]?.timeIntervalSinceNow ?? 0) * -1000) : UInt32(self.startedAt.timeIntervalSinceNow * -1000)
            self.doOutput(
                dataWasSent ? RTMPChunkType.one : RTMPChunkType.zero,
                chunkStreamId: RTMPChunk.StreamID.data.rawValue,
                message: RTMPDataMessage(
                    streamId: self.id,
                    objectEncoding: self.objectEncoding,
                    timestamp: timestmap,
                    handlerName: handlerName,
                    arguments: arguments
                )
            )
            self.dataTimestamps[handlerName] = .init()
        }
    }

    /// Creates flv metadata for a stream.
    open func makeMetaData() -> ASObject {
        var metadata: [String: Any] = [
            "duration": 0
        ]
        if !videoInputFormats.isEmpty {
            metadata["width"] = videoSettings.videoSize.width
            metadata["height"] = videoSettings.videoSize.height
            #if os(iOS) || os(macOS) || os(tvOS)
            metadata["framerate"] = frameRate
            #endif
            switch videoSettings.format {
            case .h264:
                metadata["videocodecid"] = FLVVideoCodec.avc.rawValue
            case .hevc:
                metadata["videocodecid"] = FLVVideoFourCC.hevc.rawValue
            }
            metadata["videodatarate"] = videoSettings.bitRate / 1000
        }
        if !audioInputFormats.isEmpty {
            metadata["audiocodecid"] = FLVAudioCodec.aac.rawValue
            metadata["audiodatarate"] = audioSettings.bitRate / 1000
            if let outputFormat = mixer.audioIO.outputFormat {
                metadata["audiosamplerate"] = outputFormat.sampleRate
            }
        }
        return metadata
    }

    override public func readyStateDidChange(to readyState: IOStream.ReadyState) {
        guard let connection else {
            return
        }
        switch readyState {
        case .open:
            currentFPS = 0
            frameCount = 0
            audioSampleAccess = true
            videoSampleAccess = true
            metadata.removeAll()
            info.clear()
            for message in messages {
                message.streamId = id
                message.transactionId = connection.newTransaction
                switch message.commandName {
                case "play":
                    self.readyState = .play
                case "publish":
                    self.readyState = .publish
                default:
                    break
                }
                connection.doOutput(chunk: RTMPChunk(message: message))
            }
            messages.removeAll()
        case .playing:
            startedAt = .init()
        case .publish:
            bitrateStrategy.setUp()
            startedAt = .init()
        case .publishing:
            startedAt = .init()
            let metadata = makeMetaData()
            send(handlerName: "@setDataFrame", arguments: "onMetaData", ASArray(metadata))
            self.metadata = metadata
        default:
            break
        }
        super.readyStateDidChange(to: readyState)
    }

    func close(withLockQueue: Bool) {
        if withLockQueue {
            lockQueue.sync {
                self.close(withLockQueue: false)
            }
            return
        }
        guard let connection, ReadyState.open.rawValue < readyState.rawValue else {
            return
        }
        readyState = .open
        if let fcPublishName {
            connection.call("FCUnpublish", responder: nil, arguments: fcPublishName)
            connection.call("deleteStream", responder: nil, arguments: id)
        } else {
            connection.doOutput(chunk: RTMPChunk(
                                    type: .zero,
                                    streamId: RTMPChunk.StreamID.command.rawValue,
                                    message: RTMPCommandMessage(
                                        streamId: id,
                                        transactionId: 0,
                                        objectEncoding: objectEncoding,
                                        commandName: "closeStream",
                                        commandObject: nil,
                                        arguments: []
                                    )))
        }
    }

    func doOutput(_ type: RTMPChunkType, chunkStreamId: UInt16, message: RTMPMessage) {
        message.streamId = id
        let length = connection?.doOutput(chunk: .init(
            type: type,
            streamId: chunkStreamId,
            message: message
        )) ?? 0
        info.byteCount.mutate { $0 += Int64(length) }
    }

    func on(timer: Timer) {
        currentFPS = frameCount
        frameCount = 0
        info.on(timer: timer)
    }

    func dispatch(_ message: RTMPDataMessage) {
        info.byteCount.mutate { $0 += Int64(message.payload.count) }
        switch message.handlerName {
        case "onMetaData":
            metadata = message.arguments[0] as? [String: Any?] ?? [:]
        case "|RtmpSampleAccess":
            audioSampleAccess = message.arguments[0] as? Bool ?? true
            videoSampleAccess = message.arguments[1] as? Bool ?? true
        default:
            break
        }
    }

    @objc
    private func on(status: Notification) {
        let e = Event.from(status)
        guard let connection, let data = e.data as? ASObject, let code = data["code"] as? String else {
            return
        }
        switch code {
        case RTMPConnection.Code.connectSuccess.rawValue:
            readyState = .initialized
            connection.createStream(self)
        case RTMPStream.Code.playReset.rawValue:
            readyState = .play
        case RTMPStream.Code.playStart.rawValue:
            readyState = .playing
        case RTMPStream.Code.publishStart.rawValue:
            readyState = .publishing(muxer: muxer)
        default:
            break
        }
    }
}

extension RTMPStream: EventDispatcherConvertible {
    // MARK: EventDispatcherConvertible
    public func addEventListener(_ type: Event.Name, selector: Selector, observer: AnyObject? = nil, useCapture: Bool = false) {
        dispatcher.addEventListener(type, selector: selector, observer: observer, useCapture: useCapture)
    }

    public func removeEventListener(_ type: Event.Name, selector: Selector, observer: AnyObject? = nil, useCapture: Bool = false) {
        dispatcher.removeEventListener(type, selector: selector, observer: observer, useCapture: useCapture)
    }

    public func dispatch(event: Event) {
        dispatcher.dispatch(event: event)
    }

    public func dispatch(_ type: Event.Name, bubbles: Bool, data: Any?) {
        dispatcher.dispatch(type, bubbles: bubbles, data: data)
    }
}
