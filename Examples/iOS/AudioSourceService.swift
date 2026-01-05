@preconcurrency import AVFoundation
import Combine
import HaishinKit

struct AudioSource: Sendable, Hashable, Equatable, CustomStringConvertible {
    static let empty = AudioSource(portName: "", dataSourceName: "", isSupportedStereo: false)

    let portName: String
    let dataSourceName: String
    let isSupportedStereo: Bool

    var description: String {
        if isSupportedStereo {
            return "\(portName)(\(dataSourceName))(Stereo)"
        }
        return "\(portName)(\(dataSourceName))(Mono)"
    }
}

actor AudioSourceService {
    enum Error: Swift.Error {
        case missingDataSource(_ source: AudioSource)
    }

    var buffer: AsyncStream<(AVAudioPCMBuffer, AVAudioTime)> {
        AsyncStream { continuation in
            bufferContinuation = continuation
        }
    }

    private(set) var mode: AudioSourceServiceMode = .audioEngine
    private(set) var isRunning = false
    private(set) var sources: [AudioSource] = [] {
        didSet {
            guard sources != oldValue else {
                return
            }
            continuation?.yield(sources)
        }
    }
    private let session = AVAudioSession.sharedInstance()
    private var continuation: AsyncStream<[AudioSource]>.Continuation? {
        didSet {
            oldValue?.finish()
        }
    }
    private var tasks: [Task<Void, Swift.Error>] = []
    private var audioEngineCapture: AudioEngineCapture? {
        didSet {
            audioEngineCapture?.delegate = self
        }
    }
    private var bufferContinuation: AsyncStream<(AVAudioPCMBuffer, AVAudioTime)>.Continuation? {
        didSet {
            oldValue?.finish()
        }
    }

    func setUp(_ mode: AudioSourceServiceMode) {
        self.mode = mode
        do {
            let session = AVAudioSession.sharedInstance()
            // If you set the "mode" parameter, stereo capture is not possible, so it is left unspecified.
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
            // It looks like this setting is required on iOS 18.5.
            try? session.setPreferredInputNumberOfChannels(2)
        } catch {
            logger.error(error)
        }
    }

    func sourcesUpdates() -> AsyncStream<[AudioSource]> {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.yield(sources)
        }
    }

    func selectAudioSource(_ audioSource: AudioSource) throws {
        setPreferredInputBuiltInMic(true)
        guard let preferredInput = AVAudioSession.sharedInstance().preferredInput,
              let dataSources = preferredInput.dataSources,
              let newDataSource = dataSources.first(where: { $0.dataSourceName == audioSource.dataSourceName }),
              let supportedPolarPatterns = newDataSource.supportedPolarPatterns else {
            throw Error.missingDataSource(audioSource)
        }
        do {
            let isStereoSupported = supportedPolarPatterns.contains(.stereo)
            if isStereoSupported {
                try newDataSource.setPreferredPolarPattern(.stereo)
            }
            try preferredInput.setPreferredDataSource(newDataSource)
        } catch {
            logger.warn(error)
        }
    }

    private func makeAudioSources() -> [AudioSource] {
        if session.inputDataSources?.isEmpty == true {
            setPreferredInputBuiltInMic(false)
        } else {
            setPreferredInputBuiltInMic(true)
        }
        guard let preferredInput = session.preferredInput else {
            return []
        }
        var sources: [AudioSource] = []
        for dataSource in session.preferredInput?.dataSources ?? [] {
            sources.append(.init(
                portName: preferredInput.portName,
                dataSourceName: dataSource.dataSourceName,
                isSupportedStereo: dataSource.supportedPolarPatterns?.contains(.stereo) ?? false
            ))
        }
        return sources
    }

    private func setPreferredInputBuiltInMic(_ isEnabled: Bool) {
        do {
            if isEnabled {
                guard let availableInputs = session.availableInputs,
                      let builtInMicInput = availableInputs.first(where: { $0.portType == .builtInMic }) else {
                    return
                }
                try session.setPreferredInput(builtInMicInput)
            } else {
                try session.setPreferredInput(nil)
            }
        } catch {
            logger.warn(error)
        }
    }
}

extension AudioSourceService: AsyncRunner {
    // MARK: AsyncRunner
    func startRunning() async {
        guard !isRunning else {
            return
        }
        switch mode {
        case .audioSource:
            break
        case .audioSourceWithStereo:
            sources = makeAudioSources()
            tasks.append(Task {
                for await reason in NotificationCenter.default.notifications(named: AVAudioSession.routeChangeNotification)
                    .compactMap({ $0.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt })
                    .compactMap({ AVAudioSession.RouteChangeReason(rawValue: $0) }) {
                    logger.info("route change ->", reason.rawValue)
                    sources = makeAudioSources()
                }
            })
        case .audioEngine:
            audioEngineCapture = AudioEngineCapture()
            audioEngineCapture?.startRunning()
            tasks.append(Task {
                for await reason in NotificationCenter.default.notifications(named: AVAudioSession.routeChangeNotification)
                    .compactMap({ $0.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt })
                    .compactMap({ AVAudioSession.RouteChangeReason(rawValue: $0) }) {
                    // There are cases where it crashes when executed in situations other than attaching or detaching earphones. https://github.com/HaishinKit/HaishinKit.swift/issues/1863
                    switch reason {
                    case .newDeviceAvailable, .oldDeviceUnavailable:
                        audioEngineCapture?.startCaptureIfNeeded()
                    default: ()
                    }
                }
            })
            tasks.append(Task {
                for await notification in NotificationCenter.default.notifications(
                    named: AVAudioSession.interruptionNotification,
                    object: AVAudioSession.sharedInstance()
                ) {
                    guard
                        let userInfo = notification.userInfo,
                        let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                        let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
                        return
                    }
                    switch type {
                    case .began:
                        logger.info("interruption began", notification)
                    case .ended:
                        logger.info("interruption end", notification)
                        let optionsValue =
                            userInfo[AVAudioSessionInterruptionOptionKey] as? UInt
                        let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue ?? 0)
                        if options.contains(.shouldResume) {
                            audioEngineCapture?.startCaptureIfNeeded()
                        }
                    default: ()
                    }
                }
            })
        }
        isRunning = true
    }

    func stopRunning() async {
        guard isRunning else {
            return
        }
        audioEngineCapture?.stopRunning()
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        isRunning = false
    }
}

extension AudioSourceService: AudioEngineCaptureDelegate {
    // MARK: AudioEngineCaptureDelegate
    nonisolated func audioCapture(_ audioCapture: AudioEngineCapture, buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        Task {
            await bufferContinuation?.yield((buffer, time))
        }
    }
}
