@preconcurrency import AVFoundation

// MARK: -
/// An actor represents video and audio recorder.
///
/// This actor is compatible with both StreamOutput and MediaMixerOutput. This means it can record the output from MediaMixer in addition to StreamConvertible.
///
/// ```swift
///  // An example of recording MediaMixer.
///  let recorder = StreamRecorder()
///  let mixer = MediaMixer()
///  mixer.addOutput(recorder)
/// ```
/// ```swift
///  // An example of recording streaming.
///  let recorder = StreamRecorder()
///  let mixer = MediaMixer()
///  let stream = RTMPStream()
///  mixer.addOutput(stream)
///  stream.addOutput(recorder)
/// ```
public actor StreamRecorder {
    static let defaultPathExtension = "mp4"

    /// The error domain codes.
    public enum Error: Swift.Error {
        /// An invalid internal stare.
        case invalidState
        /// The specified file already exists.
        case fileAlreadyExists(outputURL: URL)
        /// The specifiled file type is not supported.
        case notSupportedFileType(pathExtension: String)
        /// Failed to create the AVAssetWriter.
        case failedToCreateAssetWriter(error: any Swift.Error)
        /// Failed to create the AVAssetWriterInput.
        case failedToCreateAssetWriterInput(error: any Swift.Error)
        /// Failed to append the PixelBuffer or SampleBuffer.
        case failedToAppend(error: (any Swift.Error)?)
        /// Failed to finish writing the AVAssetWriter.
        case failedToFinishWriting(error: (any Swift.Error)?)
    }

    /// The default recording settings.
    public static let defaultSettings: [AVMediaType: [String: any Sendable]] = [
        .audio: [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 0,
            AVNumberOfChannelsKey: 0
        ],
        .video: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoHeightKey: 0,
            AVVideoWidthKey: 0
        ]
    ]

    private static func isZero(_ value: any Sendable) -> Bool {
        switch value {
        case let value as Int:
            return value == 0
        case let value as Double:
            return value == 0
        default:
            return false
        }
    }

    enum SupportedFileType: String {
        case mp4
        case mov

        var fileType: AVFileType {
            switch self {
            case .mp4:
                return .mp4
            case .mov:
                return .mov
            }
        }
    }

    /// The recorder settings.
    public private(set) var settings: [AVMediaType: [String: any Sendable]] = StreamRecorder.defaultSettings
    /// The recording output url.
    public var outputURL: URL? {
        return writer?.outputURL
    }
    /// The current error.
    public var error: AsyncStream<StreamRecorder.Error> {
        AsyncStream { continuation in
            self.continuation = continuation
        }
    }
    /// The recording or not.
    public private(set) var isRecording = false
    /// The the movie fragment interval in sec.
    public private(set) var movieFragmentInterval: Double?
    public private(set) var videoTrackId: UInt8? = UInt8.max
    public private(set) var audioTrackId: UInt8? = UInt8.max

    #if os(macOS) && !targetEnvironment(macCatalyst)
    /// The default file save location.
    public private(set) var moviesDirectory: URL = {
        URL(fileURLWithPath: NSSearchPathForDirectoriesInDomains(.moviesDirectory, .userDomainMask, true)[0])
    }()
    #else
    /// The default file save location.
    public private(set) lazy var moviesDirectory: URL = {
        URL(fileURLWithPath: NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0])
    }()
    #endif

    private var isReadyForStartWriting: Bool {
        guard let writer = writer else {
            return false
        }
        return settings.count == writer.inputs.count
    }
    private var writer: AVAssetWriter?
    private var continuation: AsyncStream<Error>.Continuation? {
        didSet {
            oldValue?.finish()
        }
    }
    private var writerInputs: [AVMediaType: AVAssetWriterInput] = [:]
    private var audioPresentationTime: CMTime = .invalid
    private var videoPresentationTime: CMTime = .invalid
    private var dimensions: CMVideoDimensions = .init(width: 0, height: 0)

    /// Creates a new recorder.
    public init() {
    }

    /// Sets the movie fragment interval in sec.
    ///
    /// This value allows the file to be written continuously, so the file will remain even if the app crashes or is forcefully terminated. A value of 10 seconds or more is recommended.
    /// - seealso: https://developer.apple.com/documentation/avfoundation/avassetwriter/1387469-moviefragmentinterval
    public func setMovieFragmentInterval(_ movieFragmentInterval: Double?) {
        if let movieFragmentInterval {
            self.movieFragmentInterval = max(10.0, movieFragmentInterval)
        } else {
            self.movieFragmentInterval = nil
        }
    }

    /// Starts recording.
    ///
    /// For iOS, if the URL is unspecified, the file will be saved in .documentDirectory. You can specify a folder of your choice, but please use an absolute path.
    ///
    /// ```
    /// try? await recorder.startRecording(nil)
    /// // -> $documentDirectory/B644F60F-0959-4F54-9D14-7F9949E02AD8.mp4
    ///
    /// try? await recorder.startRecording(URL(string: "dir/sample.mp4"))
    /// // -> $documentDirectory/dir/sample.mp4
    ///
    /// try? await recorder.startRecording(await recorder.moviesDirectory.appendingPathComponent("sample.mp4"))
    /// // -> $documentDirectory/sample.mp4
    ///
    /// try? await recorder.startRecording(URL(string: "dir"))
    /// // -> $documentDirectory/dir/33FA7D32-E0A8-4E2C-9980-B54B60654044.mp4
    /// ```
    ///
    /// - Note: Folders are not created automatically, so it’s expected that the target directory is created in advance.
    /// - Parameters:
    ///   - url: The file path for recording. If nil is specified, a unique file path will be returned automatically.
    ///   - settings: Settings for recording.
    /// - Throws: `Error.fileAlreadyExists` when case file already exists.
    /// - Throws: `Error.notSupportedFileType` when case species not supported format.
    public func startRecording(_ url: URL? = nil, settings: [AVMediaType: [String: any Sendable]] = StreamRecorder.defaultSettings) async throws {
        guard !isRecording else {
            throw Error.invalidState
        }

        let outputURL = makeOutputURL(url)
        if FileManager.default.fileExists(atPath: outputURL.path) {
            throw Error.fileAlreadyExists(outputURL: outputURL)
        }

        var fileType: AVFileType = .mp4
        if let supportedFileType = SupportedFileType(rawValue: outputURL.pathExtension) {
            fileType = supportedFileType.fileType
        } else {
            throw Error.notSupportedFileType(pathExtension: outputURL.pathExtension)
        }

        writer = try AVAssetWriter(outputURL: outputURL, fileType: fileType)
        if let movieFragmentInterval {
            writer?.movieFragmentInterval = CMTime(seconds: movieFragmentInterval, preferredTimescale: 1)
        }
        videoPresentationTime = .invalid
        audioPresentationTime = .invalid
        self.settings = settings

        isRecording = true
    }

    /// Stops recording.
    ///
    /// ## Example of saving to the Photos app.
    /// ```
    ///  do {
    ///    let outputURL = try await recorder.stopRecording()
    ///    PHPhotoLibrary.shared().performChanges({() -> Void in
    ///      PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: outputURL)
    ///    }, completionHandler: { _, error -> Void in
    ///      try? FileManager.default.removeItem(at: outputURL)
    ///    }
    ///  } catch {
    ///     print(error)
    ///  }
    /// ```
    public func stopRecording() async throws -> URL {
        guard isRecording else {
            throw Error.invalidState
        }
        defer {
            isRecording = false
            continuation = nil
            self.writer = nil
            self.writerInputs.removeAll()
        }
        guard let writer = writer, writer.status == .writing else {
            throw Error.failedToFinishWriting(error: writer?.error)
        }
        for (_, input) in writerInputs {
            input.markAsFinished()
        }
        await writer.finishWriting()
        return writer.outputURL
    }

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

    private func makeOutputURL(_ url: URL?) -> URL {
        guard let url else {
            return moviesDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(Self.defaultPathExtension)
        }
        // AVAssetWriter requires a isFileURL condition.
        guard url.isFileURL else {
            return url.pathExtension.isEmpty ?
                moviesDirectory.appendingPathComponent(url.path).appendingPathComponent(UUID().uuidString).appendingPathExtension(Self.defaultPathExtension) :
                moviesDirectory.appendingPathComponent(url.path)
        }
        return url.pathExtension.isEmpty ? url.appendingPathComponent(UUID().uuidString).appendingPathExtension(Self.defaultPathExtension) : url
    }

    func append(_ sampleBuffer: CMSampleBuffer) {
        guard isRecording else {
            return
        }
        let mediaType: AVMediaType = (sampleBuffer.formatDescription?.mediaType == .video) ? .video : .audio
        guard
            let writer,
            let input = makeWriterInput(mediaType, sourceFormatHint: sampleBuffer.formatDescription),
            isReadyForStartWriting else {
            return
        }

        switch writer.status {
        case .unknown:
            writer.startWriting()
            writer.startSession(atSourceTime: sampleBuffer.presentationTimeStamp)
        default:
            break
        }

        if input.isReadyForMoreMediaData {
            // Tasks delivering samples can arrive out of order. Only advance after a successful append.
            switch mediaType {
            case .audio:
                guard !audioPresentationTime.isValid || audioPresentationTime < sampleBuffer.presentationTimeStamp else {
                    return
                }
                if input.append(sampleBuffer) {
                    audioPresentationTime = sampleBuffer.presentationTimeStamp
                } else {
                    continuation?.yield(Error.failedToAppend(error: writer.error))
                }
            case .video:
                guard !videoPresentationTime.isValid || videoPresentationTime < sampleBuffer.presentationTimeStamp else {
                    return
                }
                if input.append(sampleBuffer) {
                    videoPresentationTime = sampleBuffer.presentationTimeStamp
                } else {
                    continuation?.yield(Error.failedToAppend(error: writer.error))
                }
            default:
                break
            }
        }
    }

    private func makeWriterInput(_ mediaType: AVMediaType, sourceFormatHint: CMFormatDescription?) -> AVAssetWriterInput? {
        guard writerInputs[mediaType] == nil else {
            return writerInputs[mediaType]
        }

        var outputSettings: [String: Any] = [:]
        if let settings = self.settings[mediaType] {
            switch mediaType {
            case .audio:
                guard
                    let format = sourceFormatHint,
                    let inSourceFormat = format.audioStreamBasicDescription else {
                    break
                }
                for (key, value) in settings {
                    switch key {
                    case AVSampleRateKey:
                        outputSettings[key] = Self.isZero(value) ? inSourceFormat.mSampleRate : value
                    case AVNumberOfChannelsKey:
                        outputSettings[key] = Self.isZero(value) ? Int(inSourceFormat.mChannelsPerFrame) : value
                    default:
                        outputSettings[key] = value
                    }
                }
            case .video:
                dimensions = sourceFormatHint?.dimensions ?? .init(width: 0, height: 0)
                for (key, value) in settings {
                    switch key {
                    case AVVideoHeightKey:
                        outputSettings[key] = Self.isZero(value) ? Int(dimensions.height) : value
                    case AVVideoWidthKey:
                        outputSettings[key] = Self.isZero(value) ? Int(dimensions.width) : value
                    default:
                        outputSettings[key] = value
                    }
                }
            default:
                break
            }
        }

        var input: AVAssetWriterInput?
        if writer?.canApply(outputSettings: outputSettings, forMediaType: mediaType) == true {
            input = AVAssetWriterInput(mediaType: mediaType, outputSettings: outputSettings, sourceFormatHint: sourceFormatHint)
            input?.expectsMediaDataInRealTime = true
            self.writerInputs[mediaType] = input
            if let input {
                self.writer?.add(input)
            }
        }

        return input
    }
}

extension StreamRecorder: StreamOutput {
    // MARK: HKStreamOutput
    nonisolated public func stream(_ stream: some StreamConvertible, didOutput video: CMSampleBuffer) {
        Task { await append(video) }
    }

    nonisolated public func stream(_ stream: some StreamConvertible, didOutput audio: AVAudioBuffer, when: AVAudioTime) {
        guard let sampleBuffer = (audio as? AVAudioPCMBuffer)?.makeSampleBuffer(when) else {
            return
        }
        Task { await append(sampleBuffer) }
    }
}

extension StreamRecorder: MediaMixerOutput {
    // MARK: MediaMixerOutput
    nonisolated public func mixer(_ mixer: MediaMixer, didOutput sampleBuffer: CMSampleBuffer) {
        Task {
            await append(sampleBuffer)
        }
    }

    nonisolated public func mixer(_ mixer: MediaMixer, didOutput buffer: AVAudioPCMBuffer, when: AVAudioTime) {
        guard let sampleBuffer = buffer.makeSampleBuffer(when) else {
            return
        }
        Task {
            await append(sampleBuffer)
        }
    }
}
