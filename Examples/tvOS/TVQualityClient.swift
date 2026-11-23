import Combine
import Darwin
import Foundation
import HaishinKit
import SwiftUI

@MainActor
final class TVQualityClient: NSObject, ObservableObject {
    struct Receiver: Identifiable {
        let id: String
        let name: String
        let url: URL
    }
    @Published private(set) var receivers: [Receiver] = []
    @Published private(set) var busy = false
    @Published private(set) var status = "Choose a Mac with VQMetrix Receive enabled."
    @Published var endpoint = ""
    @Published var code = ""
    @Published private(set) var packageReady = false
    private var browser: NetServiceBrowser?
    private var pending: [String: NetService] = [:]
    private var task: Task<Void, Never>?
    private var directory: URL?
    private var archive: URL?
    private var runID: UUID?
    private let recorder = TVQualityCapture()

    func browse() {
        stopBrowsing()
        let browser = NetServiceBrowser()
        browser.delegate = self
        self.browser = browser
        browser.searchForServices(ofType: "_vqmetrix._tcp.", inDomain: "local.")
    }
    func stopBrowsing() {
        browser?.delegate = nil
        browser?.stop()
        browser = nil
        pending.values.forEach {
            $0.delegate = nil
            $0.stop()
        }
        pending.removeAll()
        receivers.removeAll()
    }
    func captureAndSend(studio: TVStudioModel) {
        guard !busy, studio.canStart, studio.direction == .send else { return }
        guard validCode else {
            status = "Enter the Mac's 4-digit connection code."
            return
        }
        busy = true
        packageReady = false
        removePackage()
        let id = UUID()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("vqmetrix-\(id.uuidString)", isDirectory: true)
        directory = folder
        runID = id
        let source = studio.source == .test ? "test-pattern" : "continuity-camera"
        task = Task {
            defer { busy = false }
            do {
                _ = try await validatedEndpoint()
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                status = "Capturing 3 seconds · 640 × 360 · 15 fps…"
                await studio.mixer.addOutput(recorder)
                let frames: [Data]
                do { frames = try await recorder.capture() } catch {
                    await studio.mixer.removeOutput(recorder)
                    throw error
                }
                await studio.mixer.removeOutput(recorder)
                status = "Encoding the same reference at 0.5, 1 and 2 Mbps…"
                archive = try await recorder.makePackage(
                    frames: frames, directory: folder, runID: id, source: source, bitrates: [500_000, 1_000_000, 2_000_000])
                packageReady = true
                try await upload()
            } catch {
                status = error is CancellationError ? "Cancelled." : error.localizedDescription
            }
        }
    }
    func retry() {
        guard !busy, packageReady, validCode else { return }
        busy = true
        task = Task {
            defer { busy = false }
            do { try await upload() } catch { status = error is CancellationError ? "Cancelled." : error.localizedDescription }
        }
    }
    func cancel() { task?.cancel() }
    func close() {
        cancel()
        stopBrowsing()
        code = ""
    }
    private var validCode: Bool { code.count == 4 && code.utf8.allSatisfy { (48...57).contains($0) } }
    private func removePackage() {
        if let directory { try? FileManager.default.removeItem(at: directory) }
        directory = nil
        archive = nil
        runID = nil
    }
    private func validatedEndpoint() async throws -> URL {
        guard let base = URL(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines)),
            let scheme = base.scheme?.lowercased(), ["http", "https"].contains(scheme),
            let host = base.host, !host.isEmpty, base.user == nil, base.password == nil,
            base.query == nil, base.fragment == nil, base.path.isEmpty || base.path == "/"
        else {
            throw QualityError("Enter the receiver's HTTP(S) base address without a path.")
        }
        if scheme == "http" {
            let local = await Task.detached { TVQualityClient.localAddress(host) }.value
            guard let local else { throw QualityError("Unencrypted HTTP is limited to local network addresses. Use HTTPS for other receivers.") }
            var parts = URLComponents(url: base, resolvingAgainstBaseURL: false)!
            parts.host = local.contains(":") ? "[\(local)]" : local
            guard let pinned = parts.url else { throw QualityError("Invalid local address.") }
            return pinned.appendingPathComponent("api/v1/runs")
        }
        return base.appendingPathComponent("api/v1/runs")
    }
    private func upload() async throws {
        guard validCode, let archive, let runID else { throw QualityError("Capture a package and enter a 4-digit code first.") }
        let url = try await validatedEndpoint()
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/zip", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(code)", forHTTPHeaderField: "Authorization")
        request.setValue(runID.uuidString, forHTTPHeaderField: "Idempotency-Key")
        request.setValue("1", forHTTPHeaderField: "X-VQMetrix-Protocol")
        request.setValue(String(try archive.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0), forHTTPHeaderField: "Content-Length")
        status = "Sending evaluation package…"
        let session = URLSession(configuration: .ephemeral, delegate: TVQualityUploadDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.upload(for: request, fromFile: archive)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw QualityError("Invalid receiver response.") }
        guard [200, 201, 202].contains(response.statusCode) else {
            throw QualityError("Receiver returned HTTP \(response.statusCode). Check its connection code and queue.")
        }
        struct Receipt: Decodable {
            let jobId: UUID
            let status: String
        }
        guard data.count <= 65536, let receipt = try? JSONDecoder().decode(Receipt.self, from: data) else {
            throw QualityError("The receiver did not return a valid job receipt. Retry keeps the same run ID.")
        }
        status = "Accepted · job \(receipt.jobId.uuidString)\nOpen History on the Mac for evaluation results."
        packageReady = false
        removePackage()
    }
    nonisolated private static func localAddress(_ host: String) -> String? {
        let name = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(name, nil, &hints, &result) == 0, let first = result else { return nil }
        defer { freeaddrinfo(first) }
        var item: UnsafeMutablePointer<addrinfo>? = first
        while let current = item {
            defer { item = current.pointee.ai_next }
            let info = current.pointee
            guard let address = info.ai_addr else { continue }
            let allowed: Bool
            if info.ai_family == AF_INET {
                let ip = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
                let a = ip >> 24
                let b = (ip >> 16) & 255
                allowed = a == 10 || a == 127 || (a == 172 && (16...31).contains(b)) || (a == 192 && b == 168) || (a == 169 && b == 254)
            } else if info.ai_family == AF_INET6 {
                let bytes = address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { withUnsafeBytes(of: $0.pointee.sin6_addr) { Array($0) } }
                allowed =
                    (bytes[0] & 0xfe) == 0xfc || (bytes[0] == 0xfe && bytes[1] & 0xc0 == 0x80) || (bytes.dropLast().allSatisfy { $0 == 0 } && bytes.last == 1)
            } else {
                continue
            }
            guard allowed else { continue }
            var numeric = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, info.ai_addrlen, &numeric, socklen_t(numeric.count), nil, 0, NI_NUMERICHOST) == 0 {
                return String(cString: numeric)
            }
        }
        return nil
    }

}

extension TVQualityClient: @preconcurrency NetServiceBrowserDelegate, @preconcurrency NetServiceDelegate {
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        guard browser === self.browser else { return }
        pending[service.name]?.stop()
        pending[service.name] = service
        service.delegate = self
        service.resolve(withTimeout: 5)
    }
    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        guard browser === self.browser else { return }
        pending.removeValue(forKey: service.name)?.stop()
        receivers.removeAll { $0.id == service.name }
    }
    func netServiceDidResolveAddress(_ sender: NetService) {
        guard pending[sender.name] === sender else { return }
        pending.removeValue(forKey: sender.name)
        let txt = sender.txtRecordData().map(NetService.dictionary(fromTXTRecord:)) ?? [:]
        func value(_ key: String) -> String? { txt[key].flatMap { String(data: $0, encoding: .utf8) } }
        guard value("protocol") == "1", let scheme = value("scheme"), ["http", "https"].contains(scheme),
            let host = value("host") ?? sender.hostName, (1...65535).contains(sender.port)
        else { return }
        var parts = URLComponents()
        parts.scheme = scheme
        parts.host = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        parts.port = sender.port
        guard let url = parts.url else { return }
        receivers.removeAll { $0.id == sender.name }
        receivers.append(.init(id: sender.name, name: sender.name, url: url))
        receivers.sort { $0.name < $1.name }
    }
    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        guard browser === self.browser else { return }
        stopBrowsing()
        status = "Bonjour search failed. Enter the receiver address manually."
    }
    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        guard pending[sender.name] === sender else { return }
        pending.removeValue(forKey: sender.name)
    }
}

private final class TVQualityUploadDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) { completionHandler(nil) }
}

struct TVQualityView: View {
    @ObservedObject var client: TVQualityClient
    let studio: TVStudioModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text("Send the current video source to VQMetrix for a controlled H.264 bitrate comparison.").font(.title3)
                    Button("Find VQMetrix receivers") { client.browse() }.disabled(client.busy)
                    ForEach(client.receivers) { receiver in
                        Button(receiver.name) { client.endpoint = receiver.url.absoluteString }.disabled(client.busy)
                    }
                    TextField("http://MacName.local:8787", text: $client.endpoint).textInputAutocapitalization(.never).autocorrectionDisabled().disabled(
                        client.busy)
                    SecureField("4-digit connection code", text: $client.code).disabled(client.busy)
                    Text(
                        "3 seconds · 640 × 360 · 15 fps · H.264 at 0.5 / 1 / 2 Mbps\nThe same BT.709 reference is used for all variants. Audio is not part of VMAF evaluation. HTTP sends video and the connection code over your trusted LAN."
                    )
                    .font(.callout).foregroundStyle(.secondary)
                    Text(client.status).font(.callout)
                    if client.busy {
                        ProgressView()
                        Button("Cancel") { client.cancel() }
                    } else {
                        Button("Capture and send") { client.captureAndSend(studio: studio) }.buttonStyle(.borderedProminent)
                        if client.packageReady { Button("Retry same package") { client.retry() } }
                    }
                    Button("Done") { dismiss() }
                }.frame(maxWidth: 1280, alignment: .leading).padding(64).frame(maxWidth: .infinity)
            }.navigationTitle("VQMetrix")
        }.background(Color(white: colorScheme == .dark ? 0.08 : 0.95).ignoresSafeArea())
            .onAppear { client.browse() }.onDisappear { client.close() }
    }
}
