@preconcurrency import AVKit
import HaishinKit
import SwiftUI

@MainActor
final class PlaybackViewModel: ObservableObject {
    @Published private(set) var readyState: StreamSessionReadyState = .closed
    @Published private(set) var error: Error?
    @Published var isShowError = false

    private var view: PiPHKView?
    private var session: (any StreamSession)?
    private let audioPlayer = AudioPlayer(audioEngine: AVAudioEngine())
    private var pictureInPictureController: AVPictureInPictureController?

    func start(_ preference: PreferenceViewModel) {
        Task {
            if session == nil {
                await makeSession(preference)
            }
            do {
                try await session?.connect {
                    Task { @MainActor in
                        self.isShowError = true
                    }
                }
            } catch {
                self.error = error
                self.isShowError = true
            }
        }
    }

    func stop() {
        Task {
            do {
                try await session?.close()
            } catch {
                logger.error(error)
            }
        }
    }

    private func makeSession(_ preference: PreferenceViewModel) async {
        do {
            session = try await StreamSessionBuilderFactory.shared.make(preference.makeURL())
                .setMode(.playback)
                .build()
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
                }
            }
        } catch {
            logger.error(error)
        }
    }
}

extension PlaybackViewModel: PiPHKViewRepresentable.PreviewSource {
    // MARK: PiPHKSwiftUiView.PreviewSource
    nonisolated func connect(to view: PiPHKView) {
        Task { @MainActor in
            self.view = view
        }
    }
}
