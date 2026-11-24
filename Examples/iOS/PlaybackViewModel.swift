@preconcurrency import AVKit
import Combine
import HaishinKit
@preconcurrency import Logboard
import SwiftUI

@MainActor
final class PlaybackViewModel: ObservableObject {
    @Published private(set) var readyState: StreamSessionReadyState = .closed
    @Published private(set) var error: Error?
    @Published var hasError = false

    var friendlyErrorMessage: String {
        guard let error else {
            return "Something went wrong. Please check your connection and try again."
        }

        let errorString = String(describing: error).lowercased()

        if errorString.contains("unsupportedcommand") || errorString.contains("error 1") {
            return "This server doesn't support watching streams directly. Most streaming servers (like Owncast) require you to watch via a web browser instead."
        } else if errorString.contains("timeout") || errorString.contains("timedout") {
            return "Connection timed out. The server may be offline or the stream URL might be incorrect."
        } else if errorString.contains("invalidstate") {
            return "Unable to connect. Please check that a stream is currently live."
        } else if errorString.contains("connection") {
            return "Couldn't reach the server. Check your internet connection and verify the stream URL in Preferences."
        } else {
            return "Unable to play this stream. The server may not support direct playback, or no stream is currently live."
        }
    }

    func dismissError() {
        hasError = false
        error = nil
    }

    private var view: (any StreamOutput)?
    private var session: (any StreamSession)?
    private var sessionURL: URL?
    private var stateTask: Task<Void, Never>?
    private var sessionChangeTask: Task<Void, Never>?
    private var sessionGeneration: UInt = 0
    private let audioPlayer = AudioPlayer(audioEngine: AVAudioEngine())
    private var pictureInPictureController: AVPictureInPictureController?

    func start() async {
        guard let session else {
            return
        }
        let generation = sessionGeneration
        dismissError()
        do {
            let audioSession = AVAudioSession.sharedInstance()
            if audioSession.category != .playAndRecord {
                try audioSession.setCategory(.playback)
            }
            try audioSession.setActive(true)
            try await session.connect {
                Task { @MainActor in
                    guard generation == self.sessionGeneration else { return }
                    self.hasError = true
                }
            }
            if generation != sessionGeneration {
                try? await session.close()
            }
        } catch {
            guard generation == sessionGeneration else {
                try? await session.close()
                return
            }
            self.error = error
            self.hasError = true
        }
    }

    func stop() async {
        do {
            try await session?.close()
        } catch {
            logger.error(error)
        }
    }

    func makeSession(_ url: URL?) async {
        if let url, sessionURL == url { return }
        sessionGeneration &+= 1
        let generation = sessionGeneration
        stateTask?.cancel()
        stateTask = nil
        let previousSession = session
        let previousView = view
        session = nil
        sessionURL = nil
        readyState = .closed
        UIApplication.shared.isIdleTimerDisabled = false
        dismissError()

        // Finish earlier setup/teardown before attaching another node to the shared player.
        let previousChange = sessionChangeTask
        let change = Task { [weak self] in
            await previousChange?.value
            guard let self else { return }
            if let previousSession {
                if let previousView { await previousSession.stream.removeOutput(previousView) }
                await previousSession.stream.attachAudioPlayer(nil)
                try? await previousSession.close()
            }
            guard generation == self.sessionGeneration else { return }
            await self.prepareSession(url, generation: generation)
        }
        sessionChangeTask = change
        await change.value
    }

    private func prepareSession(_ url: URL?, generation: UInt) async {
        do {
            guard let url,
                  let candidate = try await StreamSessionBuilderFactory.shared.make(url)
                    .setMode(.playback)
                    .build() else {
                throw StreamSessionBuilderFactory.Error.illegalArgument
            }
            await candidate.setMaxRetryCount(0)
            await candidate.stream.attachAudioPlayer(audioPlayer)
            guard generation == sessionGeneration else {
                await candidate.stream.attachAudioPlayer(nil)
                try? await candidate.close()
                return
            }
            session = candidate
            sessionURL = url
            if let view {
                await candidate.stream.addOutput(view)
                if generation != sessionGeneration || self.view !== view {
                    await candidate.stream.removeOutput(view)
                }
            }
            guard generation == sessionGeneration else { return }
            stateTask = Task { [weak self] in
                for await readyState in await candidate.readyState {
                    guard !Task.isCancelled, let self, generation == self.sessionGeneration else { return }
                    self.readyState = readyState
                    switch readyState {
                    case .open:
                        self.dismissError()
                        UIApplication.shared.isIdleTimerDisabled = false
                    default:
                        UIApplication.shared.isIdleTimerDisabled = true
                    }
                }
            }
        } catch {
            guard generation == sessionGeneration else { return }
            self.error = error
            hasError = true
            logger.error(error)
        }
    }

    private func attachView(_ view: some StreamOutput) async {
        let previousView = self.view
        self.view = view
        let generation = sessionGeneration
        guard let session else { return }
        if let previousView { await session.stream.removeOutput(previousView) }
        guard self.view === view, generation == sessionGeneration else { return }
        await session.stream.addOutput(view)
        if self.view !== view || generation != sessionGeneration {
            await session.stream.removeOutput(view)
        }
    }
}

extension PlaybackViewModel: MTHKViewRepresentable.PreviewSource {
    // MARK: MTHKViewRepresentable.PreviewSource
    nonisolated func connect(to view: MTHKView) {
        Task { @MainActor in
            pictureInPictureController?.stopPictureInPicture()
            pictureInPictureController = nil
            await attachView(view)
        }
    }
}

extension PlaybackViewModel: PiPHKViewRepresentable.PreviewSource {
    // MARK: PiPHKSwiftUiView.PreviewSource
    nonisolated func connect(to view: HaishinKit.PiPHKView) {
        Task { @MainActor in
            let contentSource = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: view.layer, playbackDelegate: PlaybackDelegate())
            if let pictureInPictureController {
                pictureInPictureController.contentSource = contentSource
            } else {
                pictureInPictureController = AVPictureInPictureController(contentSource: contentSource)
            }
            await attachView(view)
        }
    }
}

final class PlaybackDelegate: NSObject, AVPictureInPictureSampleBufferPlaybackDelegate {
    // MARK: AVPictureInPictureControllerDelegate
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {
    }

    func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        return CMTimeRange(start: .zero, duration: .positiveInfinity)
    }

    func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        return false
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, skipByInterval skipInterval: CMTime, completion completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}
