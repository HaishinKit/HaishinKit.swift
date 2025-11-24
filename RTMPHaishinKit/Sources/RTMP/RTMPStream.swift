@preconcurrency import AVFAudio
import AVFoundation
import Combine
import HaishinKit

#if canImport(UIKit)
import UIKit
typealias View = UIView
#endif

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit
typealias View = NSView
#endif

/// An object that provides the interface to control a one-way channel over an RTMPConnection.
public actor RTMPStream {
    /// The error domain code.
    public enum Error: Swift.Error {
        /// An invalid internal stare.
        case invalidState
        /// The requested operation timed out.
        case requestTimedOut
        /// A request fails.
        case requestFailed(response: RTMPResponse)
        /// An unsupported codec.
        case unsupportedCodec
    }

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

        func status(_ description: String) -> RTMPStatus {
            return .init(code: rawValue, level: level, description: description)
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

    static let defaultID: UInt32 = 0
    static let supportedAudioCodecs: [AudioCodecSettings.Format] = [.aac, .opus]
    static let supportedVideoCodecs: [VideoCodecSettings.Format] = VideoCodecSettings.Format.allCases

    /// The RTMPStream metadata.
    public private(set) var metadata: AMFArray = .init(count: 0)
    /// The RTMPStreamInfo object whose properties contain data.
    public private(set) var info = RTMPStreamInfo()
    /// The object encoding (AMF). Framework supports AMF0 only.
    public private(set) var objectEncoding = RTMPConnection.defaultObjectEncoding
    /// The boolean value that indicates audio samples allow access or not.
    public private(set) var audioSampleAccess = true
    /// The boolean value that indicates video samples allow access or not.
    public private(set) var videoSampleAccess = true
    /// The number of video frames per seconds.
    @Published public private(set) var currentFPS: UInt16 = 0
    /// The ready state of stream.
    @Published public private(set) var readyState: StreamReadyState = .idle
    /// The stream of events you receive RTMP status events from a service.
    public var status: AsyncStream<RTMPStatus> {
        AsyncStream { continuation in
            statusContinuation = continuation
        }
    }
    /// The stream's name used for FMLE-compatible sequences.
    public private(set) var fcPublishName: String?

    public private(set) var videoTrackId: UInt8? = UInt8.max
    public private(set) var audioTrackId: UInt8? = UInt8.max

    private var isPaused = false
    private var startedAt = Date() {
        didSet {
            dataTimestamps.removeAll()
        }
    }
    package var outputs: [any StreamOutput] = []
    private var frameCount: UInt16 = 0
    private var audioBuffer: AVAudioCompressedBuffer?
    private var howToPublish: RTMPStream.HowToPublish = .live
    private var continuation: CheckedContinuation<RTMPResponse, any Swift.Error>? {
        didSet {
            if continuation == nil {
                expectedResponse = nil
            }
        }
    }
    private var dataTimestamps: [String: Date] = .init()
    private var audioTimestamp: RTMPTimestamp<AVAudioTime> = .init()
    private var videoTimestamp: RTMPTimestamp<CMTime> = .init()
    private var requestTimeout = RTMPConnection.defaultRequestTimeout
    private var expectedResponse: Code?
    package var bitRateStrategy: (any StreamBitRateStrategy)?
    private var statusContinuation: AsyncStream<RTMPStatus>.Continuation?
    private(set) var id: UInt32 = RTMPStream.defaultID
    package lazy var incoming = IncomingStream(self)
    package lazy var outgoing = OutgoingStream()
    private weak var connection: RTMPConnection?

    private var audioFormat: AVAudioFormat? {
        didSet {
            guard audioFormat != oldValue else {
                return
            }
            switch readyState {
            case .publishing:
                guard let message = RTMPAudioMessage(streamId: id, timestamp: 0, formatDescription: audioFormat?.formatDescription) else {
                    return
                }
                doOutput(oldValue == nil ? .zero : .one, chunkStreamId: .audio, message: message)
            case .playing:
                if let audioFormat {
                    audioBuffer = AVAudioCompressedBuffer(format: audioFormat, packetCapacity: 1, maximumPacketSize: 1024 * Int(audioFormat.channelCount))
                } else {
                    audioBuffer = nil
                }
            default:
                break
            }
        }
    }

    private var videoFormat: CMFormatDescription? {
        didSet {
            guard videoFormat != oldValue else {
                return
            }
            switch readyState {
            case .publishing:
                guard let message = RTMPVideoMessage(streamId: id, timestamp: 0, formatDescription: videoFormat) else {
                    return
                }
                doOutput(oldValue == nil ? .zero : .one, chunkStreamId: .video, message: message)
            default:
                break
            }
        }
    }

    /// Creates a new stream.
    public init(connection: RTMPConnection, fcPublishName: String? = nil) {
        self.connection = connection
        self.fcPublishName = fcPublishName
        self.requestTimeout = connection.requestTimeout
        Task {
            await connection.addStream(self)
            if await connection.connected {
                await createStream()
            }
        }
    }

    deinit {
        outputs.removeAll()
    }

    /// Plays a live stream from a server.
    public func play(_ arguments: (any Sendable)?...) async throws -> RTMPResponse {
        guard let name = arguments.first as? String else {
            switch readyState {
            case .playing:
                info.resourceName = nil
                return try await close()
            default:
                throw Error.invalidState
            }
        }
        do {
            audioFormat = nil
            videoFormat = nil
            let response = try await withCheckedThrowingContinuation { continuation in
                readyState = .play
                expectedResponse = Code.playStart
                self.continuation = continuation
                Task {
                    await incoming.startRunning()
                    try? await Task.sleep(nanoseconds: requestTimeout * 1_000_000)
                    self.continuation.map {
                        $0.resume(throwing: Error.requestTimedOut)
                    }
                    self.continuation = nil
                }
                doOutput(.zero, chunkStreamId: .command, message: RTMPCommandMessage(
                    streamId: id,
                    transactionId: 0,
                    objectEncoding: objectEncoding,
                    commandName: "play",
                    commandObject: nil,
                    arguments: arguments
                ))
            }
            startedAt = .init()
            readyState = .playing
            info.resourceName = name
            return response
        } catch {
            Task { await incoming.stopRunning() }
            outgoing.stopRunning()
            readyState = .idle
            throw error
        }
    }

    /// Seeks the keyframe.
    public func seek(_ offset: Double) async throws {
        guard readyState == .playing else {
            throw Error.invalidState
        }
        doOutput(.zero, chunkStreamId: .command, message: RTMPCommandMessage(
            streamId: id,
            transactionId: 0,
            objectEncoding: objectEncoding,
            commandName: "seek",
            commandObject: nil,
            arguments: [offset]
        ))
    }

    /// Sends streaming audio, vidoe and data message from client.
    public func publish(_ name: String?, type: RTMPStream.HowToPublish = .live) async throws -> RTMPResponse {
        guard let name else {
            switch readyState {
            case .publishing:
                return try await close()
            default:
                throw Error.invalidState
            }
        }
        do {
            audioFormat = nil
            videoFormat = nil
            let response = try await withCheckedThrowingContinuation { continuation in
                readyState = .publish
                expectedResponse = Code.publishStart
                self.continuation = continuation
                Task {
                    try? await Task.sleep(nanoseconds: requestTimeout * 1_000_000)
                    self.continuation.map {
                        $0.resume(throwing: Error.requestTimedOut)
                    }
                    self.continuation = nil
                }
                doOutput(.zero, chunkStreamId: .command, message: RTMPCommandMessage(
                    streamId: id,
                    transactionId: 0,
                    objectEncoding: objectEncoding,
                    commandName: "publish",
                    commandObject: nil,
                    arguments: [name, type.rawValue]
                ))
            }
            info.resourceName = name
            howToPublish = type
            startedAt = .init()
            metadata = makeMetadata()
            readyState = .publishing
            try? send("@setDataFrame", arguments: "onMetaData", metadata)
            outgoing.startRunning()
            Task {
                for await audio in outgoing.audioOutputStream {
                    append(audio.0, when: audio.1)
                }
            }
            Task {
                for await video in outgoing.videoOutputStream {
                    append(video)
                }
            }
            Task {
                for await video in outgoing.videoInputStream {
                    outgoing.append(video: video)
                }
            }
            return response
        } catch {
            readyState = .idle
            throw error
        }
    }

    /// Stops playing or publishing and makes available other uses.
    public func close() async throws -> RTMPResponse {
        guard readyState == .playing || readyState == .publishing else {
            throw Error.invalidState
        }
        outgoing.stopRunning()
        return try await withCheckedThrowingContinuation { continutation in
            self.continuation = continutation
            switch readyState {
            case .playing:
                expectedResponse = Code.playStop
            case .publishing:
                expectedResponse = Code.unpublishSuccess
            default:
                break
            }
            Task {
                await incoming.stopRunning()
                try? await Task.sleep(nanoseconds: requestTimeout * 1_000_000)
                self.continuation.map {
                    $0.resume(throwing: Error.requestTimedOut)
                }
                self.continuation = nil
            }
            doOutput(.zero, chunkStreamId: .command, message: RTMPCommandMessage(
                streamId: id,
                transactionId: 0,
                objectEncoding: objectEncoding,
                commandName: "closeStream",
                commandObject: nil,
                arguments: []
            ))
            readyState = .idle
        }
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
    ///   - arguments: Optional arguments.
    ///   - isResetTimestamp: A workaround option for sending timestamps as 0 in some services.
    public func send(_ handlerName: String, arguments: (any Sendable)?..., isResetTimestamp: Bool = false) throws {
        guard readyState == .publishing else {
            throw Error.invalidState
        }
        if isResetTimestamp {
            dataTimestamps[handlerName] = nil
        }
        let dataWasSent = dataTimestamps[handlerName] == nil ? false : true
        let timestmap: UInt32 = dataWasSent ? UInt32((dataTimestamps[handlerName]?.timeIntervalSinceNow ?? 0) * -1000) : UInt32(startedAt.timeIntervalSinceNow * -1000)
        doOutput(
            dataWasSent ? RTMPChunkType.one : RTMPChunkType.zero,
            chunkStreamId: .data,
            message: RTMPDataMessage(
                streamId: id,
                objectEncoding: objectEncoding,
                timestamp: timestmap,
                handlerName: handlerName,
                arguments: arguments
            )
        )
        dataTimestamps[handlerName] = .init()
    }

    /// Incoming audio plays on a stream or not.
    public func receiveAudio(_ receiveAudio: Bool) async throws {
        guard readyState == .playing else {
            throw Error.invalidState
        }
        doOutput(.zero, chunkStreamId: .command, message: RTMPCommandMessage(
            streamId: id,
            transactionId: 0,
            objectEncoding: objectEncoding,
            commandName: "receiveAudio",
            commandObject: nil,
            arguments: [receiveAudio]
        ))
    }

    /// Incoming video plays on a stream or not.
    public func receiveVideo(_ receiveVideo: Bool) async throws {
        guard readyState == .playing else {
            throw Error.invalidState
        }
        doOutput(.zero, chunkStreamId: .command, message: RTMPCommandMessage(
            streamId: id,
            transactionId: 0,
            objectEncoding: objectEncoding,
            commandName: "receiveVideo",
            commandObject: nil,
            arguments: [receiveVideo]
        ))
    }

    /// Pauses playback a  stream or not.
    public func pause(_ paused: Bool) async throws -> RTMPResponse {
        guard readyState == .playing else {
            throw Error.invalidState
        }
        let response = try await withCheckedThrowingContinuation { continuation in
            expectedResponse = isPaused ? Code.pauseNotify : Code.unpauseNotify
            self.continuation = continuation
            Task {
                try? await Task.sleep(nanoseconds: requestTimeout * 1_000_000)
                self.continuation.map {
                    $0.resume(throwing: Error.requestTimedOut)
                }
                self.continuation = nil
            }
            doOutput(.zero, chunkStreamId: .command, message: RTMPCommandMessage(
                streamId: id,
                transactionId: 0,
                objectEncoding: objectEncoding,
                commandName: "pause",
                commandObject: nil,
                arguments: [paused, floor(startedAt.timeIntervalSinceNow * -1000)]
            ))
        }
        isPaused = paused
        return response
    }

    /// Pauses or resumes playback of a stream.
    public func togglePause() async throws -> RTMPResponse {
        try await pause(!isPaused)
    }

    func doOutput(_ type: RTMPChunkType, chunkStreamId: RTMPChunkStreamId, message: some RTMPMessage) {
        Task {
            let length = await connection?.doOutput(type, chunkStreamId: chunkStreamId, message: message) ?? 0
            info.byteCount += length
        }
    }

    func dispatch(_ message: some RTMPMessage, type: RTMPChunkType) {
        info.byteCount += message.payload.count
        switch message {
        case let message as RTMPCommandMessage:
            let response = RTMPResponse(message)
            switch message.commandName {
            case "onStatus":
                switch response.status?.level {
                case "status":
                    // During playback, only NetStream.Play.Start is awaited, as it follows the next sequence.
                    // 1. NetStream.Play.Rest
                    // 2. NetStream.Play.Start
                    if let code = response.status?.code, expectedResponse?.rawValue == code {
                        continuation?.resume(returning: response)
                        continuation = nil
                    }
                default:
                    continuation?.resume(throwing: Error.requestFailed(response: response))
                    continuation = nil
                }
                _ = response.status.map {
                    statusContinuation?.yield($0)
                }
            default:
                logger.info(message)
            }
        case let message as RTMPAudioMessage:
            append(message, type: type)
        case let message as RTMPVideoMessage:
            append(message, type: type)
        case let message as RTMPDataMessage:
            switch message.handlerName {
            case "onMetaData":
                metadata = message.arguments[0] as? AMFArray ?? .init(count: 0)
            case "|RtmpSampleAccess":
                audioSampleAccess = message.arguments[0] as? Bool ?? true
                videoSampleAccess = message.arguments[1] as? Bool ?? true
            default:
                break
            }
        case let message as RTMPUserControlMessage:
            switch message.event {
            case .bufferEmpty:
                statusContinuation?.yield(Code.bufferEmpty.status(""))
            case .bufferFull:
                statusContinuation?.yield(Code.bufferFull.status(""))
            default:
                break
            }
        default:
            break
        }
    }

    func createStream() async {
        if let fcPublishName {
            // FMLE-compatible sequences
            async let _ = connection?.call("releaseStream", arguments: fcPublishName)
            async let _ = connection?.call("FCPublish", arguments: fcPublishName)
        }
        do {
            let response = try await connection?.call("createStream")
            guard let first = response?.arguments.first as? Double else {
                return
            }
            id = UInt32(first)
            readyState = .idle
        } catch {
            logger.error(error)
        }
    }

    func deleteStream() async {
        guard let fcPublishName, readyState == .publishing else {
            return
        }
        outgoing.stopRunning()
        async let _ = try? connection?.call("FCUnpublish", arguments: fcPublishName)
        async let _ = try? connection?.call("deleteStream", arguments: id)
    }

    private func append(_ message: RTMPAudioMessage, type: RTMPChunkType) {
        audioTimestamp.update(message, chunkType: type)
        guard message.codec.isSupported else {
            return
        }
        switch message.payload[1] {
        case RTMPAACPacketType.seq.rawValue:
            audioFormat = message.makeAudioFormat()
        case RTMPAACPacketType.raw.rawValue:
            if audioFormat == nil {
                audioFormat = message.makeAudioFormat()
            }
            if let audioBuffer {
                message.copyMemory(audioBuffer)
                Task { await incoming.append(audioBuffer, when: audioTimestamp.value) }
            }
        default:
            break
        }
    }

    private func append(_ message: RTMPVideoMessage, type: RTMPChunkType) {
        videoTimestamp.update(message, chunkType: type)
        guard RTMPTagType.video.headerSize <= message.payload.count && message.isSupported else {
            return
        }
        if message.isExHeader {
            // IsExHeader for Enhancing RTMP, FLV
            switch message.packetType {
            case RTMPVideoPacketType.sequenceStart.rawValue:
                videoFormat = message.makeFormatDescription()
            case RTMPVideoPacketType.codedFrames.rawValue:
                Task { await incoming.append(message, presentationTimeStamp: videoTimestamp.value, formatDesciption: videoFormat) }
            case RTMPVideoPacketType.codedFramesX.rawValue:
                Task { await incoming.append(message, presentationTimeStamp: videoTimestamp.value, formatDesciption: videoFormat) }
            default:
                break
            }
        } else {
            switch message.packetType {
            case RTMPAVCPacketType.seq.rawValue:
                videoFormat = message.makeFormatDescription()
            case RTMPAVCPacketType.nal.rawValue:
                Task { await incoming.append(message, presentationTimeStamp: videoTimestamp.value, formatDesciption: videoFormat) }
            default:
                break
            }
        }
    }

    /// Creates flv metadata for a stream.
    private func makeMetadata() -> AMFArray {
        // https://github.com/shogo4405/HaishinKit.swift/issues/1410
        var metadata: AMFObject = ["duration": 0]
        if outgoing.videoInputFormat != nil {
            metadata["width"] = outgoing.videoSettings.videoSize.width
            metadata["height"] = outgoing.videoSettings.videoSize.height
            metadata["videocodecid"] = outgoing.videoSettings.format.codecid
            metadata["videodatarate"] = outgoing.videoSettings.bitRate / 1000
            if let expectedFrameRate = outgoing.videoSettings.expectedFrameRate {
                metadata["framerate"] = outgoing.videoSettings.expectedFrameRate
            }
        }
        if let audioFormat = outgoing.audioInputFormat?.audioStreamBasicDescription {
            metadata["audiocodecid"] = outgoing.audioSettings.format.codecid
            metadata["audiodatarate"] = outgoing.audioSettings.bitRate / 1000
            metadata["audiosamplerate"] = outgoing.audioSettings.format.makeSampleRate(
                audioFormat.mSampleRate,
                output: outgoing.audioSettings.sampleRate
            )
        }
        return AMFArray(metadata)
    }
}

extension RTMPStream: _Stream {
    public func setAudioSettings(_ audioSettings: AudioCodecSettings) throws {
        guard Self.supportedAudioCodecs.contains(audioSettings.format) else {
            throw Error.unsupportedCodec
        }
        outgoing.audioSettings = audioSettings
    }

    public func setVideoSettings(_ videoSettings: VideoCodecSettings) throws {
        guard Self.supportedVideoCodecs.contains(videoSettings.format) else {
            throw Error.unsupportedCodec
        }
        outgoing.videoSettings = videoSettings
    }

    public func append(_ sampleBuffer: CMSampleBuffer) {
        switch sampleBuffer.formatDescription?.mediaType {
        case .video:
            if sampleBuffer.formatDescription?.isCompressed == true {
                do {
                    let decodeTimeStamp = sampleBuffer.decodeTimeStamp.isValid ? sampleBuffer.decodeTimeStamp : sampleBuffer.presentationTimeStamp
                    let timedelta = try videoTimestamp.update(decodeTimeStamp)
                    frameCount += 1
                    videoFormat = sampleBuffer.formatDescription
                    guard let message = RTMPVideoMessage(streamId: id, timestamp: timedelta, sampleBuffer: sampleBuffer) else {
                        return
                    }
                    doOutput(.one, chunkStreamId: .video, message: message)
                } catch {
                    logger.warn(error)
                }
            } else {
                outgoing.append(sampleBuffer)
                if sampleBuffer.formatDescription?.isCompressed == false {
                    outputs.forEach {
                        switch sampleBuffer.formatDescription?.mediaType {
                        case .audio:
                            if audioSampleAccess {
                                $0.stream(self, didOutput: sampleBuffer)
                            }
                        case .video:
                            if videoSampleAccess || ($0 is View) {
                                $0.stream(self, didOutput: sampleBuffer)
                            }
                        default:
                            $0.stream(self, didOutput: sampleBuffer)
                        }
                    }
                }
            }
        default:
            break
        }
    }

    public func append(_ audioBuffer: AVAudioBuffer, when: AVAudioTime) {
        switch audioBuffer {
        case let audioBuffer as AVAudioCompressedBuffer:
            do {
                let timedelta = try audioTimestamp.update(when)
                audioFormat = audioBuffer.format
                guard let message = RTMPAudioMessage(streamId: id, timestamp: timedelta, audioBuffer: audioBuffer) else {
                    return
                }
                doOutput(.one, chunkStreamId: .audio, message: message)
            } catch {
                logger.warn(error)
            }
        default:
            outgoing.append(audioBuffer, when: when)
            if audioBuffer is AVAudioPCMBuffer && audioSampleAccess {
                outputs.forEach { $0.stream(self, didOutput: audioBuffer, when: when) }
            }
        }
    }

    public func dispatch(_ event: NetworkMonitorEvent) async {
        await bitRateStrategy?.adjustBitrate(event, stream: self)
        currentFPS = frameCount
        frameCount = 0
        info.update()
    }
}

extension RTMPStream: MediaMixerOutput {
    // MARK: MediaMixerOutput
    public func selectTrack(_ id: UInt8?, mediaType: CMFormatDescription.MediaType) {
        switch mediaType {
        case .audio:
            audioTrackId = id
        case .video:
            videoTrackId = id
        default:
            break
        }
    }

    nonisolated public func mixer(_ mixer: MediaMixer, didOutput sampleBuffer: CMSampleBuffer) {
        Task { await append(sampleBuffer) }
    }

    nonisolated public func mixer(_ mixer: MediaMixer, didOutput buffer: AVAudioPCMBuffer, when: AVAudioTime) {
        Task { await append(buffer, when: when) }
    }
}
