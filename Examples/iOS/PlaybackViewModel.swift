@preconcurrency import AVKit
import Combine
import HaishinKit
@preconcurrency import Logboard
import SwiftUI

@MainActor
final class PlaybackViewModel: ObservableObject {
    @Published private(set) var readyState: SessionReadyState = .closed
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

    private var view: PiPHKView?
    private var session: (any Session)?
    private let audioPlayer = AudioPlayer(audioEngine: AVAudioEngine())
    private var pictureInPictureController: AVPictureInPictureController?

    func start() async {
        guard let session else {
            return
        }
        do {
            try await session.connect {
                Task { @MainActor in
                    self.hasError = true
                }
            }
        } catch {
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

    func makeSession() async {
        do {
            session = try await SessionBuilderFactory.shared.make(Preference.default.makeURL())
                .setMode(.playback)
                .build()
            await session?.setMaxRetryCount(0)
            guard let session else {
                return
            }
            if let view {
                await session.stream.addOutput(view)
            }
            await session.stream.attachAudioPlayer(audioPlayer)
            Task {
                for await readyState in await session.readyState {
                    self.readyState = readyState
                    switch readyState {
                    case .open:
                        UIApplication.shared.isIdleTimerDisabled = false
                    default:
                        UIApplication.shared.isIdleTimerDisabled = true
                    }
                }
            }
        } catch {
            logger.error(error)
        }
    }
}

extension PlaybackViewModel: MTHKViewRepresentable.PreviewSource {
    // MARK: MTHKViewRepresentable.PreviewSource
    nonisolated func connect(to view: MTHKView) {
        Task { @MainActor in
        }
    }
}

extension PlaybackViewModel: PiPHKViewRepresentable.PreviewSource {
    // MARK: PiPHKSwiftUiView.PreviewSource
    nonisolated func connect(to view: HaishinKit.PiPHKView) {
        Task { @MainActor in
            self.view = view
            if pictureInPictureController == nil {
                pictureInPictureController = AVPictureInPictureController(contentSource: .init(sampleBufferDisplayLayer: view.layer, playbackDelegate: PlaybackDelegate()))
            }
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
