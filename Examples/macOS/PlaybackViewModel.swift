@preconcurrency import AVKit
import HaishinKit
import SwiftUI
import SRTHaishinKit

@MainActor
final class PlaybackViewModel: ObservableObject {
    @Published private(set) var isBusy = false
    @Published private(set) var readyState: StreamSessionReadyState = .closed
    @Published private(set) var error: Error?
    @Published var isShowError = false
    @Published private(set) var isWaitingForSender = false
    let discovery = SRTBonjourDiscovery()
    @Published private(set) var receiverSummary: String?

    private var receiverMonitor: Task<Void, Never>?
    private var receiver: SRTConnection?
    private var receiverStream: SRTStream?
    private var receiverFinished = true
    private var announcementTask: Task<Void, Never>?
    let preview: PreviewController = { let preview = PreviewController(); preview.renderer = .pip; return preview }()
    private var connectionTask: Task<Void, Never>?
    private var stopTask: Task<Void, Never>?
    private var stateTask: Task<Void, Never>?
    private var session: (any StreamSession)?
    private let audioPlayer = AudioPlayer(audioEngine: AVAudioEngine())


    func start(_ preference: PreferenceViewModel, endpoint: URL? = nil) {
        guard !isBusy, readyState == .closed else { return }
        isBusy = true
        let previousStop = stopTask
        connectionTask = Task {
            await previousStop?.value
            defer { isBusy = false }
            stateTask?.cancel()
            session = nil
            await makeSession(preference, endpoint: endpoint)
            guard let session, !Task.isCancelled else { return }
            do {
                try await session.connect {
                    Task { @MainActor in
                        self.isShowError = true
                    }
                }
                if Task.isCancelled { try? await session.close() }
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error
                self.isShowError = true
            }
        }
    }

    func listen(port: Int) {
        guard !isBusy, readyState == .closed, (1...65535).contains(port) else { return }
        isBusy = true
        receiverFinished = false
        let previousStop = stopTask
        connectionTask = Task {
            await previousStop?.value
            defer { isBusy = false; receiverFinished = true }
            guard !Task.isCancelled else { return }
            stateTask?.cancel()
            session = nil
            receiverSummary = nil
            let connection = SRTConnection()
            let stream = SRTStream(connection: connection)
            receiver = connection
            receiverStream = stream
            await stream.addOutput(preview)
            await stream.attachAudioPlayer(audioPlayer)
            guard !Task.isCancelled else { return }
            readyState = .connecting
            announcementTask = Task {
                while await connection.uri == nil {
                    guard !Task.isCancelled else { return }
                    try? await Task.sleep(for: .milliseconds(20))
                }
                guard !Task.isCancelled else { return }
                discovery.advertiseReceiver(port: port)
                isWaitingForSender = true
                isBusy = false
            }
            do {
                try await connection.connect(URL(string: "srt://:\(port)?mode=listener"))
                announcementTask?.cancel()
                discovery.stopAdvertising()
                guard !Task.isCancelled else { await connection.close(); return }
                await stream.play()
                isWaitingForSender = false
                readyState = .open
                receiverMonitor = Task { [weak self] in
                    while !Task.isCancelled {
                        guard let self else { return }
                        if !(await connection.connected) {
                            self.readyState = .closed
                            self.receiverSummary = nil
                            return
                        }
                        if let stats = await connection.performanceData {
                            self.receiverSummary = String(format: NSLocalizedString("SRT RX %.0f kbps · RTT %.1f ms · Lost packets %d", comment: "SRT receive metrics"), stats.mbpsRecvRate * 1000, stats.msRTT, stats.pktRcvLoss)
                        }
                        try? await Task.sleep(for: .seconds(1))
                    }
                }

            } catch {
                announcementTask?.cancel()
                discovery.stopAdvertising()
                isWaitingForSender = false
                readyState = .closed
                guard !Task.isCancelled else { return }
                self.error = error
                isShowError = true
            }
        }
    }

    func stop() {
        preview.closeFloatingPreview()

        connectionTask?.cancel()
        let connection = connectionTask
        isBusy = true
        receiverMonitor?.cancel()
        receiverMonitor = nil
        receiverSummary = nil
        discovery.stopAdvertising()
        announcementTask?.cancel()
        stopTask = Task {
            if let receiver {
                while await receiver.uri == nil && !receiverFinished {
                    try? await Task.sleep(for: .milliseconds(20))
                }
                await receiver.close()
            }
            try? await session?.close()
            await connection?.value
            defer { isBusy = false; isWaitingForSender = false }
            receiver = nil
            receiverStream = nil
            do {
                try await session?.close()
                stateTask?.cancel()
                stateTask = nil
                readyState = .closed
            } catch {
                logger.error(error)
            }
        }
    }

    private func makeSession(_ preference: PreferenceViewModel, endpoint: URL? = nil) async {
        do {
            session = try await StreamSessionBuilderFactory.shared.make(endpoint ?? preference.makeURL())
                .setMode(.playback)
                .build()
            guard let session else {
                return
            }
            await session.stream.addOutput(preview)
            await session.stream.attachAudioPlayer(audioPlayer)
            stateTask = Task { [weak self] in
                for await readyState in await session.readyState {
                    self?.readyState = readyState
                }
            }
        } catch {
            self.error = error
            self.isShowError = true
            logger.error(error)
        }
    }
}
