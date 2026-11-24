import AVKit
import HaishinKit
import Logboard
import Testing

let logger = LBLogger.with("com.haishinkit.PlaybackTests")

@MainActor @Suite(.serialized)
struct IOSPlaybackTests {
    @Test func invalidReplacementCannotReconnectThePreviousEndpoint() async throws {
        await StreamSessionBuilderFactory.shared.register(PlaybackTestFactory())
        let model = PlaybackViewModel()
        for invalid in [URL(string: "unsupported://localhost/live"), nil] {
            await model.makeSession(URL(string: "playback-test://localhost/valid"))
            let previous = try #require(model.testedSession as? PlaybackTestSession)
            await model.makeSession(invalid)
            #expect(model.testedSession == nil)
            #expect(model.readyState == .closed)
            #expect(model.hasError)
            #expect(await previous.testStream.hasAudioPlayer == false)
            let retry = Task { await model.start() }
            for _ in 0..<10 { await Task.yield() }
            if await previous.connectCount > 0 { await previous.finishConnection(failure: true) }
            await retry.value
            #expect(await previous.connectCount == 0)
        }
        await model.makeSession(URL(string: "playback-test://localhost/valid"))
        #expect(model.testedSession != nil)
        #expect(!model.hasError)
        await model.makeSession(nil)
    }

    @Test(arguments: [false, true])
    func lateConnectionCannotAffectTheNewEndpoint(failure: Bool) async throws {
        await StreamSessionBuilderFactory.shared.register(PlaybackTestFactory())
        let model = PlaybackViewModel()
        await model.makeSession(URL(string: "playback-test://localhost/first"))
        let previous = try #require(model.testedSession as? PlaybackTestSession)
        let start = Task { await model.start() }
        try await waitUntil { await previous.connectCount == 1 }
        await model.makeSession(URL(string: "playback-test://localhost/second"))
        let current = try #require(model.testedSession as? PlaybackTestSession)
        #expect(previous !== current)
        #expect(await previous.testStream.hasAudioPlayer == false)
        await previous.finishConnection(failure: failure)
        await start.value
        await previous.notifyDisconnected()
        for _ in 0..<10 { await Task.yield() }
        #expect(!model.hasError)
        #expect(await previous.connected == false)
        #expect(await current.connectCount == 0)
        #expect(await current.testStream.hasAudioPlayer)
        await model.makeSession(nil)
    }

    @Test func rendererSwitchesReplaceTheOutputAndPiPLayer() async throws {
        await StreamSessionBuilderFactory.shared.register(PlaybackTestFactory())
        let model = PlaybackViewModel()
        await model.makeSession(URL(string: "playback-test://localhost/renderers"))
        let session = try #require(model.testedSession as? PlaybackTestSession)
        let first = PiPHKView(frame: .zero)
        model.connect(to: first)
        try await waitUntil { await session.testStream.contains(first) }
        if AVPictureInPictureController.isPictureInPictureSupported() {
            #expect(model.testedPiPLayer === first.layer)
        }
        let metal = MTHKView(frame: .zero)
        model.connect(to: metal)
        try await waitUntil { await session.testStream.contains(metal) }
        #expect(await session.testStream.contains(first) == false)
        #expect(model.testedPiPLayer == nil)
        let second = PiPHKView(frame: .zero)
        model.connect(to: second)
        try await waitUntil { await session.testStream.contains(second) }
        #expect(await session.testStream.contains(metal) == false)
        if AVPictureInPictureController.isPictureInPictureSupported() {
            #expect(model.testedPiPLayer === second.layer)
        }
        await model.makeSession(nil)
        #expect(await session.testStream.contains(second) == false)
    }

    @Test func rtmpsIncludesTheSeparateStreamName() {
        let preferences = PreferenceViewModel()
        let savedURI = preferences.uri
        let savedName = preferences.streamName
        defer {
            preferences.uri = savedURI
            preferences.streamName = savedName
        }
        preferences.streamName = "camera"
        for scheme in ["rtmp", "rtmps"] {
            preferences.uri = "\(scheme)://localhost/live"
            #expect(preferences.makeURL()?.absoluteString == "\(scheme)://localhost/live/camera")
        }
        preferences.uri = "https://localhost/whep?token=test"
        #expect(preferences.makeURL()?.absoluteString == preferences.uri)
    }

    private func waitUntil(_ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !(await condition()), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(await condition())
    }
}

private struct PlaybackTestFactory: StreamSessionFactory, Sendable {
    let supportedProtocols: Set<String> = ["playback-test"]
    func make(_ uri: URL, mode: StreamSessionMode, configuration: (any StreamSessionConfiguration)?) -> any StreamSession {
        PlaybackTestSession(uri: uri, mode: mode, configuration: configuration)
    }
}

private actor PlaybackTestSession: StreamSession {
    enum Failure: Error { case connection }
    let testStream = PlaybackTestStream()
    var stream: any StreamConvertible { testStream }
    let readyState: AsyncStream<StreamSessionReadyState>
    private let states: AsyncStream<StreamSessionReadyState>.Continuation
    private var pendingConnection: CheckedContinuation<Void, Error>?
    private var disconnected: (@Sendable () -> Void)?
    private(set) var connected = false
    private(set) var connectCount = 0

    init(uri: URL, mode: StreamSessionMode, configuration: (any StreamSessionConfiguration)?) {
        (readyState, states) = AsyncStream.makeStream()
        states.yield(.closed)
    }

    func setMaxRetryCount(_ maxRetryCount: Int) {}

    func connect(_ disconnected: @Sendable @escaping () -> Void) async throws {
        connectCount += 1
        self.disconnected = disconnected
        states.yield(.connecting)
        try await withCheckedThrowingContinuation { pendingConnection = $0 }
        connected = true
        states.yield(.open)
    }

    func finishConnection(failure: Bool) {
        if failure { pendingConnection?.resume(throwing: Failure.connection) } else { pendingConnection?.resume() }
        pendingConnection = nil
    }

    func notifyDisconnected() { disconnected?() }

    func close() {
        // Reproduce RTMPSession's early return during a pending handshake.
        guard connected else { return }
        connected = false
        states.yield(.closed)
    }
}

private actor PlaybackTestStream: StreamConvertible {
    let readyState: StreamReadyState = .idle
    let audioSettings = AudioCodecSettings.default
    let videoSettings = VideoCodecSettings.default
    let soundTransform: SoundTransform? = nil
    let videoTrackId: UInt8? = nil
    let audioTrackId: UInt8? = nil
    private(set) var hasAudioPlayer = false
    private var outputs: [any StreamOutput] = []
    func contains(_ output: some StreamOutput) -> Bool { outputs.contains { $0 === output } }
    func attachAudioPlayer(_ player: AudioPlayer?) { hasAudioPlayer = player != nil }
    func addOutput(_ output: some StreamOutput) { outputs.append(output) }
    func removeOutput(_ output: some StreamOutput) { outputs.removeAll { $0 === output } }
    func setBitRateStrategy(_ strategy: (some StreamBitRateStrategy)?) {}
    func setAudioSettings(_ settings: AudioCodecSettings) {}
    func setVideoSettings(_ settings: VideoCodecSettings) {}
    func setSoundTransform(_ transform: SoundTransform) {}
    func setVideoInputBufferCounts(_ counts: Int) {}
    func append(_ sample: CMSampleBuffer) {}
    func append(_ buffer: AVAudioBuffer, when: AVAudioTime) {}
    func dispatch(_ event: NetworkMonitorEvent) {}
    nonisolated func mixer(_ mixer: MediaMixer, didOutput sample: CMSampleBuffer) {}
    nonisolated func mixer(_ mixer: MediaMixer, didOutput buffer: AVAudioPCMBuffer, when: AVAudioTime) {}
    func selectTrack(_ id: UInt8?, mediaType: CMFormatDescription.MediaType) {}
}
