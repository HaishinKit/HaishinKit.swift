@preconcurrency import AVFoundation
import AVKit
import Combine
import HaishinKit
import RTCHaishinKit
import RTMPHaishinKit
import SRTHaishinKit
import SwiftUI

@MainActor
final class TVStudioModel: ObservableObject {
    enum Transport: String, CaseIterable {
        case srt = "SRT"
        case rtmp = "RTMP"
        case webRTC = "WebRTC"
    }
    enum Direction: String {
        case receive = "Receive"
        case send = "Send"
    }
    enum Source: String {
        case test = "Test signal"
        case camera = "Continuity Camera"
    }
    enum Phase: String {
        case idle = "Ready"
        case connecting = "Connecting"
        case listening = "Waiting for peer"
        case live = "Live"
        case stopping = "Stopping"
    }
    @Published private(set) var transport: Transport = .srt
    @Published private(set) var direction: Direction = .receive
    @Published private(set) var source: Source = .test
    @Published private(set) var phase: Phase = .idle {
        didSet { UIApplication.shared.isIdleTimerDisabled = phase != .idle }
    }
    @Published private(set) var isPreparing = false
    @Published private(set) var cameraName: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var networkSummary = "No SRT connection"
    @Published private(set) var probe = TVMediaProbe()
    @Published var isListener = true
    @Published var port = "9710"
    @Published var endpoint = ""
    @Published var rtcBindAddress = ""
    @Published var videoBitRate = 2_500_000
    @Published private(set) var muted = false
    let discovery = TVBonjourDiscovery()
    let mixer = MediaMixer()
    var canConfigure: Bool { phase == .idle && !isPreparing }
    var canStart: Bool { canConfigure && (direction == .receive || source == .test || cameraName != nil) }
    var requiredRole: TVBonjourDiscovery.Role { direction == .send ? .receiver : .source }
    var isActive: Bool { phase != .idle }
    private let signal = TVTestSignal()
    private let microphone = TVMicrophoneCapture()
    private let playbackEngine = AVAudioEngine()
    private lazy var audioPlayer = AudioPlayer(audioEngine: playbackEngine)
    private var preview: PiPHKView?
    private var connection: SRTConnection?
    private var stream: SRTStream?
    private var otherSession: (any StreamSession)?
    private var otherStream: (any StreamConvertible)?
    private var connectionTask: Task<Void, Never>?
    private var announcementTask: Task<Void, Never>?
    private var monitorTask: Task<Void, Never>?
    private var connectFinished = true
    private var generation = 0
    private var previewRunning = false
    private var captureGeneration = 0
    private var cameraDevice: AVContinuityDevice?
    private var cameraObserver: NSKeyValueObservation?
    private var launchArgumentsApplied = false

    func bindPreview(_ view: PiPHKView) async {
        if let old = preview {
            await mixer.removeOutput(old)
            await stream?.removeOutput(old)
        }
        if let old = preview { await otherStream?.removeOutput(old) }
        preview = view
        if direction == .send {
            await mixer.addOutput(view)
        } else if let stream {
            await stream.addOutput(view)
        } else if let otherStream {
            await otherStream.addOutput(view)
        }
    }

    func selectTransport(_ transport: Transport) async {
        guard canConfigure, self.transport != transport else { return }
        self.transport = transport
        endpoint = ""
        isListener = transport == .srt && direction == .receive
        discovery.stopBrowsing()
        if transport == .srt && !isListener { discovery.browse() }
    }

    func selectDirection(
        _ direction: Direction
    ) async {
        guard canConfigure, direction != self.direction else { return }
        isPreparing = true
        await pausePreview()
        self.direction = direction
        endpoint = ""
        isListener = transport == .srt && direction == .receive
        muted = false
        errorMessage = nil
        preview?.layer.flushAndRemoveImage()
        isPreparing = false
        await preparePreview()
        if transport == .srt && !isListener { discovery.browse() }
    }

    func preparePreview() async {
        guard !isPreparing, !previewRunning else { return }
        isPreparing = true
        defer { isPreparing = false }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            guard direction == .send, !previewRunning else { return }
            probe = TVMediaProbe()
            await mixer.setAudioMixerSettings(.init(sampleRate: 48_000, channels: 2, isMuted: muted))
            await mixer.setVideoMixerSettings(.init(mode: .passthrough))
            try await mixer.setFrameRate(30)
            await mixer.addOutput(probe)
            if let preview { await mixer.addOutput(preview) }
            await mixer.startRunning()
            previewRunning = true
            if source == .test { try signal.start(mixer: mixer) } else if let cameraDevice, cameraDevice.isConnected { try await configureCamera(cameraDevice) }
        } catch { if !(error is CancellationError) { errorMessage = (error as? StudioError)?.errorDescription ?? String(describing: error) } }
    }

    func selectSource(_ source: Source) async {
        guard canConfigure, source != self.source else { return }
        isPreparing = true
        await pausePreview()
        self.source = source
        muted = false
        cameraName = nil
        cameraDevice = nil
        cameraObserver = nil
        preview?.layer.flushAndRemoveImage()
        isPreparing = false
        await preparePreview()
    }

    func useCamera(_ device: AVContinuityDevice) async {
        guard canConfigure, source == .camera else { return }
        if !previewRunning { await preparePreview() }
        guard canConfigure, previewRunning else { return }
        isPreparing = true
        defer { isPreparing = false }
        do {
            try await configureCamera(device)
            cameraDevice = device
            cameraObserver = device.observe(\.isConnected, options: [.new]) { [weak self] device, _ in
                guard !device.isConnected else { return }
                Task { @MainActor in
                    guard let self, self.cameraDevice === device else { return }
                    self.cameraName = nil
                    self.cameraDevice = nil
                    self.cameraObserver = nil
                    guard self.direction == .send, self.source == .camera else { return }
                    await self.stop()
                    await self.pausePreview()
                    self.errorMessage = "Continuity Camera disconnected. Choose a device again or switch to the test signal."
                    self.preview?.layer.flushAndRemoveImage()
                }
            }
        } catch {
            microphone.stop()
            try? await mixer.attachVideo(nil)
            cameraName = nil
            cameraDevice = nil
            cameraObserver = nil
            if !(error is CancellationError) { errorMessage = (error as? StudioError)?.errorDescription ?? String(describing: error) }
        }
    }

    private func configureCamera(_ device: AVContinuityDevice) async throws {
        let captureRun = captureGeneration
        guard let video = device.videoDevices.first, let input = device.audioSessionInputs.first else {
            throw StudioError.message("The selected device does not provide both a camera and microphone.")
        }
        guard await AVCaptureDevice.requestAccess(for: .video) else { throw StudioError.message("Allow camera access in Settings.") }
        guard captureRun == captureGeneration else { throw CancellationError() }
        let audioAllowed = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard captureRun == captureGeneration else { throw CancellationError() }
        guard audioAllowed else { throw StudioError.message("Allow microphone access in Settings.") }
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .videoChat)
        try audioSession.setActive(true)
        try audioSession.setPreferredInput(input)
        signal.stop()
        try await mixer.attachVideo(video)
        guard captureRun == captureGeneration else { throw CancellationError() }
        try microphone.start(mixer: mixer)
        cameraName = video.localizedName
    }

    func selectService(_ service: TVBonjourDiscovery.Service) {
        guard canConfigure, service.role == requiredRole, let url = service.url else { return }
        endpoint = url.absoluteString
    }

    func start() {
        guard canStart else { return }
        if transport != .srt {
            startOtherProtocol()
            return
        }
        errorMessage = nil
        let url: URL
        if isListener {
            guard let portNumber = Int(port), (1...65535).contains(portNumber), let listener = URL(string: "srt://:\(portNumber)?mode=listener") else {
                errorMessage = "Enter a port between 1 and 65535."
                return
            }
            url = listener
        } else {
            guard var components = URLComponents(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines)),
                components.scheme?.lowercased() == "srt", let host = components.host, !host.isEmpty,
                let port = components.port, (1...65535).contains(port)
            else {
                errorMessage = "Choose a Bonjour peer or enter an srt://host:port URL."
                return
            }
            components.scheme = "srt"
            components.queryItems = (components.queryItems ?? []).filter { $0.name.lowercased() != "mode" } + [.init(name: "mode", value: "caller")]
            guard let caller = components.url else { return }
            url = caller
        }
        generation += 1
        let run = generation
        let direction = direction
        let listener = isListener
        let portNumber = Int(port) ?? 9710
        phase = .connecting
        let connection = SRTConnection()
        let stream = SRTStream(connection: connection)
        self.connection = connection
        self.stream = stream
        connectFinished = false
        connectionTask = Task {
            defer { connectFinished = true }
            do {
                if direction == .receive {
                    probe = TVMediaProbe()
                    await stream.addOutput(probe)
                    if let preview { await stream.addOutput(preview) }
                    await stream.attachAudioPlayer(audioPlayer)
                    await stream.setSoundTransform(.init(volume: muted ? 0 : 1))
                } else {
                    var video = await stream.videoSettings
                    video.videoSize = CGSize(width: 1280, height: 720)
                    video.bitRate = videoBitRate
                    video.expectedFrameRate = 30
                    #if targetEnvironment(simulator)
                        video.isHardwareAcceleratedEnabled = false
                    #endif
                    try await stream.setVideoSettings(video)
                    try await stream.setAudioSettings(.init(bitRate: 128_000, sampleRate: 48_000))
                    await stream.setExpectedMedias([.audio, .video])
                    await mixer.addOutput(stream)
                }
                guard run == generation, !Task.isCancelled else { return }
                if listener {
                    announcementTask = Task {
                        while await connection.uri == nil && !connectFinished {
                            guard run == generation, !Task.isCancelled else { return }
                            try? await Task.sleep(for: .milliseconds(20))
                        }
                        guard run == generation, !Task.isCancelled, await connection.uri != nil else { return }
                        discovery.advertise(port: portNumber, role: direction == .receive ? .receiver : .source)
                        phase = .listening
                    }
                }
                try await connection.connect(url)
                announcementTask?.cancel()
                discovery.stopAdvertising()
                guard run == generation, !Task.isCancelled else {
                    await connection.close()
                    return
                }
                if direction == .receive { await stream.play() } else { await stream.publish() }
                guard run == generation, !Task.isCancelled else {
                    await stream.close()
                    return
                }
                phase = .live
                monitorTask = Task {
                    while run == generation && !Task.isCancelled {
                        if !(await connection.connected) {
                            await stop()
                            return
                        }
                        if let stats = await connection.performanceData {
                            let rate = direction == .send ? stats.mbpsSendRate : stats.mbpsRecvRate
                            let loss = direction == .send ? stats.pktSndLoss : stats.pktRcvLoss
                            networkSummary = String(format: "%@ %.2f Mbps · RTT %.1f ms · Loss %d", direction == .send ? "TX" : "RX", rate, stats.msRTT, loss)
                        }
                        try? await Task.sleep(for: .seconds(1))
                    }
                }
            } catch {
                announcementTask?.cancel()
                discovery.stopAdvertising()
                await mixer.removeOutput(stream)
                await stream.attachAudioPlayer(nil)
                await connection.close()
                await stream.close()
                guard run == generation, !Task.isCancelled else { return }
                phase = .idle
                errorMessage = "SRT connection failed: \(error)"
            }
        }
    }

    func stop() async {
        if transport != .srt {
            await stopOtherProtocol()
            return
        }
        guard phase != .idle, phase != .stopping else { return }
        phase = .stopping
        generation += 1
        connectionTask?.cancel()
        announcementTask?.cancel()
        monitorTask?.cancel()
        discovery.stopAdvertising()
        let connecting = connectionTask
        if let connection {
            // SRTConnection.close must run after socket.open has bound its listener.
            while await connection.uri == nil && !connectFinished { try? await Task.sleep(for: .milliseconds(20)) }
            await connection.close()
        }
        await connecting?.value
        if let stream {
            await mixer.removeOutput(stream)
            await stream.attachAudioPlayer(nil)
            await stream.close()
        }
        connection = nil
        stream = nil
        connectionTask = nil
        monitorTask = nil
        probe.resetAudioLevel()
        networkSummary = "No SRT connection"
        if direction == .receive { preview?.layer.flushAndRemoveImage() }
        phase = .idle
    }

    func toggleMute() async {
        muted.toggle()
        if direction == .send {
            await mixer.setAudioMixerSettings(.init(sampleRate: 48_000, channels: 2, isMuted: muted))
        } else {
            await stream?.setSoundTransform(.init(volume: muted ? 0 : 1))
            await otherStream?.setSoundTransform(.init(volume: muted ? 0 : 1))
        }
    }

    func prepareOtherProtocols() async {
        guard canConfigure else { return }
        isPreparing = true
        await pausePreview()
        isPreparing = false
    }

    private func startOtherProtocol() {
        let text = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let schemes = transport == .rtmp ? ["rtmp", "rtmps"] : ["http", "https"]
        guard let url = URL(string: text), let scheme = url.scheme, schemes.contains(scheme), let host = url.host, !host.isEmpty,
            !url.path.isEmpty
        else {
            errorMessage = transport == .rtmp ? "Enter a full rtmp://host/app/stream URL." : "Enter the full HTTP(S) WHIP or WHEP endpoint."
            return
        }
        errorMessage = nil
        phase = .connecting
        generation += 1
        let run = generation
        let direction = direction
        let transport = transport
        connectionTask = Task {
            do {
                // Build directly to avoid a race with app-level factory registration.
                var rtcConfiguration = HTTPSessionConfiguration()
                if !rtcBindAddress.isEmpty { rtcConfiguration.bindAddress = rtcBindAddress }
                let session =
                    transport == .rtmp
                    ? RTMPSessionFactory().make(url, mode: direction == .send ? .publish : .playback, configuration: nil)
                    : HTTPSessionFactory().make(url, mode: direction == .send ? .publish : .playback, configuration: rtcConfiguration)
                otherSession = session
                await session.setMaxRetryCount(0)
                let media = await session.stream
                otherStream = media
                if direction == .send {
                    var video = await media.videoSettings
                    video.videoSize = CGSize(width: 1280, height: 720)
                    video.bitRate = videoBitRate
                    video.expectedFrameRate = 30
                    #if targetEnvironment(simulator)
                        video.isHardwareAcceleratedEnabled = false
                    #endif
                    try await media.setVideoSettings(video)
                    try await media.setAudioSettings(.init(bitRate: 128_000, sampleRate: 48_000, format: transport == .webRTC ? .opus : .aac))
                    await mixer.addOutput(media)
                } else {
                    probe = TVMediaProbe()
                    await media.addOutput(probe)
                    if let preview { await media.addOutput(preview) }
                    await media.attachAudioPlayer(audioPlayer)
                    await media.setSoundTransform(.init(volume: muted ? 0 : 1))
                }
                guard run == generation, !Task.isCancelled else { throw CancellationError() }
                try await session.connect { [weak self] in
                    Task { @MainActor in
                        guard let self, self.generation == run else { return }
                        self.errorMessage = "The server disconnected."
                        await self.stop()
                    }
                }
                // HTTP signaling finishes before ICE/DTLS. Report Live only once media transport connects.
                for _ in 0..<150 {
                    guard run == generation, !Task.isCancelled else { throw CancellationError() }
                    if await session.connected { break }
                    try await Task.sleep(for: .milliseconds(100))
                }
                guard await session.connected else { throw StudioError.message("Media transport timed out. Check server ICE addresses and firewall settings.") }
                guard run == generation, !Task.isCancelled else { throw CancellationError() }
                phase = .live
                monitorTask = Task {
                    while run == generation && !Task.isCancelled {
                        if !(await session.connected) {
                            await stop()
                            return
                        }
                        if let rtmp = media as? RTMPStream, direction == .receive {
                            let info = await rtmp.info
                            networkSummary = String(format: "RTMP RX %.2f Mbps", Double(info.currentBytesPerSecond) * 8 / 1_000_000)
                        } else {
                            networkSummary = transport == .rtmp ? "RTMP connected · H.264 / AAC" : "WebRTC connected · H.264 / Opus"
                        }
                        try? await Task.sleep(for: .seconds(1))
                    }
                }
            } catch {
                if run == generation {
                    let message = (error as? StudioError)?.errorDescription ?? String(describing: error)
                    await cleanupOtherProtocol()
                    phase = .idle
                    if !(error is CancellationError) { errorMessage = "Connection failed: \(message)" }
                }
            }
        }
    }

    private func cleanupOtherProtocol() async {
        if let otherStream {
            await mixer.removeOutput(otherStream)
            await otherStream.attachAudioPlayer(nil)
        }
        do { try await otherSession?.close() } catch { errorMessage = "Could not close the server session: \(error)" }
        if let rtc = otherStream as? RTCStream { await rtc.close() }
        otherSession = nil
        otherStream = nil
        probe.resetAudioLevel()
        networkSummary = "No connection"
        if direction == .receive { preview?.layer.flushAndRemoveImage() }
    }

    private func stopOtherProtocol() async {
        guard phase != .idle, phase != .stopping else { return }
        phase = .stopping
        generation += 1
        connectionTask?.cancel()
        monitorTask?.cancel()
        await connectionTask?.value
        await cleanupOtherProtocol()
        connectionTask = nil
        monitorTask = nil
        phase = .idle
    }

    func dismissError() { errorMessage = nil }
    func shutdown() async {
        await stop()
        await pausePreview()
        discovery.stopBrowsing()
        discovery.stopAdvertising()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    private func pausePreview() async {
        captureGeneration += 1
        cameraName = nil
        signal.stop()
        microphone.stop()
        try? await mixer.attachVideo(nil)
        await mixer.stopRunning()
        await mixer.removeOutput(probe)
        if let preview { await mixer.removeOutput(preview) }
        previewRunning = false
    }

    func applyLaunchArguments() async {
        #if DEBUG
            guard !launchArgumentsApplied else { return }
            launchArgumentsApplied = true
            let arguments = ProcessInfo.processInfo.arguments
            if let bind = arguments.firstIndex(of: "--ice-bind"), arguments.indices.contains(bind + 1) { rtcBindAddress = arguments[bind + 1] }
            if let index = arguments.firstIndex(where: { $0 == "--publish" || $0 == "--play" }), arguments.indices.contains(index + 1) {
                let url = arguments[index + 1]
                await selectDirection(arguments[index] == "--publish" ? .send : .receive)
                await selectTransport(url.hasPrefix("rtmp") ? .rtmp : .webRTC)
                endpoint = url
                start()
            } else if let index = arguments.firstIndex(of: "--srt-listen"), arguments.indices.contains(index + 1) {
                port = arguments[index + 1]
                start()
            } else if let index = arguments.firstIndex(of: "--srt-source"), arguments.indices.contains(index + 1) {
                await selectDirection(.send)
                port = arguments[index + 1]
                isListener = true
                start()
            } else if let index = arguments.firstIndex(of: "--srt-receive"), arguments.indices.contains(index + 1) {
                endpoint = arguments[index + 1]
                isListener = false
                discovery.browse()
                start()
            } else if let index = arguments.firstIndex(of: "--srt-send"), arguments.indices.contains(index + 1) {
                await selectDirection(.send)
                endpoint = arguments[index + 1]
                isListener = false
                start()
            }
        #endif
    }

    private enum StudioError: LocalizedError {
        case message(String)
        var errorDescription: String? {
            if case .message(let value) = self { return value }
            return nil
        }
    }
}
