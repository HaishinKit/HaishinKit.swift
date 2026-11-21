import AVFoundation
import HaishinKit
@preconcurrency import ScreenCaptureKit
import SwiftUI

/// Keeps screen capture separate from publishing: sharing can be previewed before going live.
@MainActor
final class ScreenCaptureSource: NSObject, ObservableObject {
    @Published private(set) var isCapturing = false
    @Published private(set) var isBusy = false
    @Published private(set) var errorMessage: String?
    private let mixer: MediaMixer
    private var stream: SCStream?
    private var configuration: SCStreamConfiguration?
    private var revision = 0
    private var output: ScreenCaptureOutput?
    private var consumer: Task<Void, Never>?
    private var observing = false
    private var active = true
    var frameRate: Int = 30

    init(mixer: MediaMixer) {
        self.mixer = mixer
    }

    func chooseContent() {
        active = true
        errorMessage = nil
        let picker = SCContentSharingPicker.shared
        if !observing {
            picker.add(self)
            observing = true
        }
        var configuration = SCContentSharingPickerConfiguration()
        configuration.allowedPickerModes = [.singleDisplay, .singleWindow, .singleApplication]
        if let bundleID = Bundle.main.bundleIdentifier {
            configuration.excludedBundleIDs = [bundleID]
        }
        picker.defaultConfiguration = configuration
        picker.isActive = true
        if let stream { picker.present(for: stream) }
        else { picker.present() }
    }

    func stop(restoreCamera: Bool = true) async {
        active = false
        revision += 1
        isBusy = true
        let current = stream
        stream = nil
        configuration = nil
        do { try await current?.stopCapture() }
        catch { errorMessage = error.localizedDescription }
        consumer?.cancel()
        consumer = nil
        output = nil
        isCapturing = false
        if observing {
            SCContentSharingPicker.shared.remove(self)
            SCContentSharingPicker.shared.isActive = false
            observing = false
        }
        if restoreCamera {
            let camera = AVCaptureDevice.authorizationStatus(for: .video) == .authorized ? AVCaptureDevice.default(for: .video) : nil
            do { try await mixer.attachVideo(camera, track: 0) }
            catch { errorMessage = error.localizedDescription }
        }
        isBusy = false
    }

    private func capture(_ filter: SCContentFilter) async {
        guard active, !isBusy else { return }
        isBusy = true
        let operation = revision
        defer { if revision == operation { isBusy = false } }
        errorMessage = nil
        do {
            if let stream {
                try await stream.updateContentFilter(filter)
                return
            }
            let configuration = SCStreamConfiguration()
            configuration.width = 1280
            configuration.height = 720
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(frameRate))
            configuration.pixelFormat = kCVPixelFormatType_32BGRA
            configuration.queueDepth = 3
            configuration.showsCursor = true
            configuration.capturesAudio = false
            configuration.scalesToFit = true
            let frames = AsyncStream<CMSampleBuffer>.makeStream(bufferingPolicy: .bufferingNewest(1))
            let output = ScreenCaptureOutput(continuation: frames.continuation)
            let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
            try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: DispatchQueue(label: "com.haishinkit.screen-capture"))
            try await mixer.attachVideo(nil, track: 0)
            guard active, operation == revision else { return }
            self.configuration = configuration
            self.output = output
            self.stream = stream
            consumer = Task { [mixer] in
                for await frame in frames.stream {
                    guard !Task.isCancelled else { break }
                    await mixer.append(frame, track: 0)
                }
            }
            try await stream.startCapture()
            guard active, operation == revision else {
                try? await stream.stopCapture()
                return
            }
            isCapturing = true
        } catch {
            guard operation == revision else { return }
            errorMessage = error.localizedDescription
            await stop()
        }
    }

    func setFrameRate(_ value: Int) {
        frameRate = value
        guard let stream, let configuration else { return }
        Task {
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(value))
            do { try await stream.updateConfiguration(configuration) }
            catch { errorMessage = error.localizedDescription }
        }
    }
}

extension ScreenCaptureSource: SCContentSharingPickerObserver, SCStreamDelegate {
    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) { }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        Task { @MainActor [weak self] in
            guard let self, stream == nil || self.stream === stream else { return }
            await self.capture(filter)
        }
    }

    nonisolated func contentSharingPickerStartDidFailWithError(_ error: Error) {
        Task { @MainActor [weak self] in self?.errorMessage = error.localizedDescription }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self, self.stream === stream else { return }
            self.errorMessage = error.localizedDescription
            await self.stop()
        }
    }
}

private final class ScreenCaptureOutput: NSObject, SCStreamOutput {
    let continuation: AsyncStream<CMSampleBuffer>.Continuation

    init(continuation: AsyncStream<CMSampleBuffer>.Continuation) {
        self.continuation = continuation
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let status = attachments.first?[.status] as? Int,
              status == SCFrameStatus.complete.rawValue else { return }
        continuation.yield(sampleBuffer)
    }

    deinit { continuation.finish() }
}

struct ScreenSourceControls: View {
    @ObservedObject var source: ScreenCaptureSource

    var body: some View {
        StudioSection(title: "Video source", subtitle: source.isCapturing ? "Sharing your selected content" : "Camera preview") {
            Button {
                source.chooseContent()
            } label: {
                Label(source.isCapturing ? "Change shared content…" : "Share screen or window…", systemImage: "rectangle.on.rectangle")
                    .frame(maxWidth: .infinity)
            }.disabled(source.isBusy)
            if source.isCapturing {
                Button("Stop sharing · Use camera") {
                    Task { await source.stop() }
                }.disabled(source.isBusy)
            }
            if source.isBusy { ProgressView("Updating source…").controlSize(.small) }
            if let error = source.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.red).textSelection(.enabled)
            }
            Text("Choose content in the macOS sharing picker. Microphone audio follows Settings → Capture.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }
}
