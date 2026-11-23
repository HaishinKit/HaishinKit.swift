import Foundation
import HaishinKit
import SwiftUI

@MainActor
final class VQMetrixModel: ObservableObject {
    @Published var host = "http://127.0.0.1:8787"
    @Published var code = ""
    @Published private(set) var busy = false
    @Published private(set) var message = String(localized: "Capture 3 seconds of the composed preview at 640 × 360, 15 fps.")
    @Published private(set) var hasPackage = false
    @Published private(set) var sampleDescription: String?
    private var directory: URL?
    private var archive: URL?
    private var runID = UUID()
    private var task: Task<Void, Never>?

    var endpoint: URL? { try? VQMetrixTransfer.endpoint(host) }
    var endpointError: String? {
        do { _ = try VQMetrixTransfer.endpoint(host); return nil }
        catch { return error.localizedDescription }
    }
    var canSend: Bool { endpoint != nil && code.count == 4 && code.allSatisfy({ $0.isASCII && $0.isNumber }) }

    func capture(mixer: MediaMixer, codec: VQMetrixCodec, bitrate: Int) {
        guard !busy else { return }
        busy = true
        task = Task {
            let capture = VQMetrixCapture()
            var workingDirectory: URL?
            do {
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent("vqmetrix-\(UUID().uuidString)", isDirectory: true)
                workingDirectory = folder
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                await mixer.addOutput(capture)
                let deadline = ContinuousClock.now + .seconds(12)
                while try capture.progress() < VQMetrixCapture.count {
                    try Task.checkCancellation()
                    guard ContinuousClock.now < deadline else { throw VQMetrixError(message: String(localized: "Video capture timed out. Check that the preview is running.")) }
                    message = String(localized: "Capturing \(try capture.progress()) / \(VQMetrixCapture.count) frames…")
                    try await Task.sleep(for: .milliseconds(100))
                }
                capture.stop()
                await mixer.removeOutput(capture)
                message = String(localized: "Encoding and packaging…")
                let id = UUID()
                let packaging = Task.detached {
                    try await capture.package(in: folder, id: id, codec: codec, bitrate: bitrate)
                }
                let file = try await withTaskCancellationHandler {
                    try await packaging.value
                } onCancel: {
                    packaging.cancel()
                }
                try Task.checkCancellation()
                clearPackage()
                directory = folder
                archive = file
                runID = id
                hasPackage = true
                sampleDescription = "\(codec.label) · \(bitrate / 1000) kbps · 640 × 360 · 15 fps"
                message = String(localized: "Ready to upload. The saved reference is re-encoded offline; audio and network effects are excluded.")
            } catch {
                capture.stop()
                await mixer.removeOutput(capture)
                if let workingDirectory { try? FileManager.default.removeItem(at: workingDirectory) }
                message = error is CancellationError ? String(localized: "Capture cancelled.") : error.localizedDescription
            }
            busy = false
            task = nil
        }
    }

    func upload() {
        guard !busy, let archive, let endpoint, canSend else { return }
        busy = true
        message = String(localized: "Uploading…")
        let code = code
        let id = runID
        task = Task {
            defer { busy = false; task = nil }
            do {
                let job = try await VQMetrixTransfer().send(file: archive, endpoint: endpoint, code: code, id: id)
                message = String(localized: "Accepted by VQMetrix: \(job.uuidString). Check the receiver for evaluation results.")
            } catch {
                message = Task.isCancelled || error is CancellationError ?
                    String(localized: "Upload cancelled. You can retry the same package.") :
                    String(localized: "\(error.localizedDescription) You can retry the same package.")
            }
        }
    }
    func cancel() {
        guard busy else { return }
        message = String(localized: "Cancelling…")
        task?.cancel()
    }
    func clearPackage() {
        if let directory { try? FileManager.default.removeItem(at: directory) }
        directory = nil
        archive = nil
        hasPackage = false
        sampleDescription = nil
    }
    deinit {
        task?.cancel()
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }
}

struct VQMetrixPanel: View {
    @ObservedObject var publisher: PublishViewModel
    @StateObject private var model = VQMetrixModel()
    @State private var codec: VQMetrixCodec = .h264

    var body: some View {
        StudioSection(title: "VQMetrix", subtitle: String(localized: "Capture and upload a quality comparison")) {
            Text(String(localized: "Start Receive in VQMetrix, then enter its address and connection code. HTTP sends video and the code unencrypted; use a trusted network."))
                .font(.caption).foregroundStyle(.secondary)
            TextField(String(localized: "Receiver URL"), text: $model.host).disabled(model.busy)
            SecureField(String(localized: "4-digit connection code"), text: $model.code).disabled(model.busy)
            Picker(String(localized: "Evaluation codec"), selection: $codec) {
                ForEach(VQMetrixCodec.allCases) { Text($0.label).tag($0) }
            }.disabled(model.busy)
            Button(String(localized: "Capture preview sample")) {
                model.capture(mixer: publisher.mixer, codec: codec, bitrate: publisher.videoBitRate)
            }.disabled(model.busy || publisher.captureIsStarting)
            Text(String(localized: "Uses the evaluation codec and Encoder video bitrate at 640 × 360, 15 fps. AV1/VP8/VP9 require an IVF-capable VQMetrix receiver."))
                .font(.caption).foregroundStyle(.secondary)
            if model.hasPackage {
                if let sampleDescription = model.sampleDescription {
                    Text(sampleDescription).font(.caption).foregroundStyle(.secondary)
                }
                Button(String(localized: "Upload sample")) { model.upload() }.disabled(model.busy || !model.canSend)
            }
            if let error = model.endpointError { Text(error).font(.caption).foregroundStyle(.secondary) }
            if model.busy {
                HStack { ProgressView().controlSize(.small); Button(String(localized: "Cancel")) { model.cancel() } }
            }
            Text(model.message).font(.caption).textSelection(.enabled)
        }
        .onDisappear { model.cancel() }
    }
}
