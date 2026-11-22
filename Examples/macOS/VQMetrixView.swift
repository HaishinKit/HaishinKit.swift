import Foundation
import HaishinKit
import SwiftUI

final class VQMetrixTransfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private var response = Data()
    private var continuation: CheckedContinuation<UUID, Error>?
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        // The delegate queue is serial. Never retain an unbounded server response.
        guard response.count + data.count <= 65_536 else { dataTask.cancel(); return }
        response.append(data)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let continuation else { return }
        self.continuation = nil
        if let error { continuation.resume(throwing: error); return }
        guard let http = task.response as? HTTPURLResponse, [200, 201, 202].contains(http.statusCode) else {
            let status = (task.response as? HTTPURLResponse)?.statusCode ?? 0
            continuation.resume(throwing: VQMetrixError(message: "Receiver returned HTTP \(status). Check reception and the connection code."))
            return
        }
        struct Receipt: Decodable { let jobId: UUID }
        guard let receipt = try? JSONDecoder().decode(Receipt.self, from: response) else {
            continuation.resume(throwing: VQMetrixError(message: "Invalid receiver receipt.")); return
        }
        continuation.resume(returning: receipt.jobId)
    }
    func send(file: URL, endpoint: URL, code: String, id: UUID) async throws -> UUID {
        var request = URLRequest(url: endpoint.appendingPathComponent("api/v1/runs"))
        request.httpMethod = "POST"
        request.setValue("application/zip", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(code)", forHTTPHeaderField: "Authorization")
        request.setValue("1", forHTTPHeaderField: "X-VQMetrix-Protocol")
        request.setValue(id.uuidString, forHTTPHeaderField: "Idempotency-Key")
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 512 * 1024 * 1024 else { throw VQMetrixError(message: "Package exceeds the receiver's 512 MiB limit.") }
        request.setValue(String(size), forHTTPHeaderField: "Content-Length")
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 180
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        // Delegate callbacks enforce a bounded response before accepting the receipt.
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                session.uploadTask(with: request, fromFile: file).resume()
            }
        } onCancel: {
            session.invalidateAndCancel()
        }
    }
}

@MainActor
final class VQMetrixModel: ObservableObject {
    @Published var host = "http://127.0.0.1:8787"
    @Published var code = ""
    @Published private(set) var busy = false
    @Published private(set) var message = "Capture 3 seconds of the composed preview at 640 × 360, 15 fps."
    @Published private(set) var hasPackage = false
    @Published private(set) var sampleDescription: String?
    private var directory: URL?
    private var archive: URL?
    private var runID = UUID()
    private var task: Task<Void, Never>?

    var endpoint: URL? {
        guard let url = URL(string: host.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let hostname = url.host, !hostname.isEmpty, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil, ["", "/"].contains(url.path) else { return nil }
        return url
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
                while capture.progress() < VQMetrixCapture.count {
                    try Task.checkCancellation()
                    guard ContinuousClock.now < deadline else { throw VQMetrixError(message: "Video capture timed out. Check that the preview is running.") }
                    message = "Capturing \(capture.progress()) / \(VQMetrixCapture.count) frames…"
                    try await Task.sleep(for: .milliseconds(100))
                }
                capture.stop()
                await mixer.removeOutput(capture)
                message = "Encoding and packaging…"
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
                message = "Ready to upload. The saved reference is re-encoded offline; audio and network effects are excluded."
            } catch {
                capture.stop()
                await mixer.removeOutput(capture)
                if let workingDirectory { try? FileManager.default.removeItem(at: workingDirectory) }
                message = error is CancellationError ? "Capture cancelled." : error.localizedDescription
            }
            busy = false
            task = nil
        }
    }

    func upload() {
        guard !busy, let archive, let endpoint, canSend else { return }
        busy = true
        message = "Uploading…"
        let code = code
        let id = runID
        task = Task {
            defer { busy = false; task = nil }
            do {
                let job = try await VQMetrixTransfer().send(file: archive, endpoint: endpoint, code: code, id: id)
                message = "Accepted by VQMetrix: \(job.uuidString). Check the receiver for evaluation results."
            } catch {
                message = "\(error.localizedDescription) You can retry the same package."
            }
        }
    }
    func cancel() { task?.cancel() }
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
        StudioSection(title: "VQMetrix", subtitle: "Capture and upload a quality comparison") {
            Text("Start Receive in VQMetrix, then enter its address and connection code. HTTP sends video and the code unencrypted; use a trusted network.")
                .font(.caption).foregroundStyle(.secondary)
            TextField("Receiver URL", text: $model.host).disabled(model.busy)
            SecureField("4-digit connection code", text: $model.code).disabled(model.busy)
            Picker("Evaluation codec", selection: $codec) {
                ForEach(VQMetrixCodec.allCases) { Text($0.label).tag($0) }
            }.disabled(model.busy)
            Button("Capture preview sample") {
                model.capture(mixer: publisher.mixer, codec: codec, bitrate: publisher.videoBitRate)
            }.disabled(model.busy || publisher.captureIsStarting)
            Text("Uses the evaluation codec and Encoder video bitrate at 640 × 360, 15 fps. AV1/VP8/VP9 require an IVF-capable VQMetrix receiver.")
                .font(.caption).foregroundStyle(.secondary)
            if model.hasPackage {
                if let sampleDescription = model.sampleDescription {
                    Text(sampleDescription).font(.caption).foregroundStyle(.secondary)
                }
                Button("Upload sample") { model.upload() }.disabled(model.busy || !model.canSend)
            }
            if model.endpoint == nil { Text("Enter an HTTP or HTTPS base URL, including the port.").font(.caption).foregroundStyle(.secondary) }
            if model.busy {
                HStack { ProgressView().controlSize(.small); Button("Cancel") { model.cancel() } }
            }
            Text(model.message).font(.caption).textSelection(.enabled)
        }
        .onDisappear { model.cancel() }
    }
}
