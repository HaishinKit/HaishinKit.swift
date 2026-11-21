import Foundation
import SwiftUI

/// `_srt._udp` is the example's opt-in discovery convention, not automatic SRT discovery.
@MainActor
final class SRTBonjourDiscovery: NSObject, ObservableObject {
    struct Service: Identifiable {
        let id: String
        let name: String
        let host: String
        let port: Int
        let isReceiver: Bool

        var url: URL? {
            var components = URLComponents()
            components.scheme = "srt"
            components.host = host
            components.port = port
            components.queryItems = [URLQueryItem(name: "mode", value: "caller")]
            return components.url
        }
    }

    @Published private(set) var services: [Service] = []
    @Published private(set) var isBrowsing = false
    @Published private(set) var isAdvertising = false
    @Published private(set) var errorMessage: String?
    private var browser: NetServiceBrowser?
    private var resolving: [String: NetService] = [:]
    private var advertisement: NetService?

    private func key(_ service: NetService) -> String {
        "\(service.domain)/\(service.type)/\(service.name)"
    }

    func startBrowsing() {
        guard browser == nil else { return }
        errorMessage = nil
        let browser = NetServiceBrowser()
        browser.delegate = self
        self.browser = browser
        isBrowsing = true
        browser.searchForServices(ofType: "_srt._udp.", inDomain: "local.")
    }

    func advertiseReceiver(port: Int) {
        stopAdvertising()
        errorMessage = nil
        let service = NetService(domain: "local.", type: "_srt._udp.",
                                 name: "HaishinKit Receiver – \(Host.current().localizedName ?? "Mac")", port: Int32(port))
        service.delegate = self
        service.setTXTRecord(NetService.data(fromTXTRecord: [
            "role": Data("receiver".utf8), "version": Data("1".utf8)
        ]))
        advertisement = service
        service.publish()
    }

    func stopAdvertising() {
        advertisement?.stop()
        advertisement = nil
        isAdvertising = false
    }

    func stop() {
        browser?.stop()
        browser = nil
        resolving.values.forEach { $0.stop() }
        resolving.removeAll()
        services.removeAll()
        isBrowsing = false
        stopAdvertising()
    }
}

// NetService callbacks are scheduled on the main run loop where browsing and publishing start.
extension SRTBonjourDiscovery: @preconcurrency NetServiceBrowserDelegate, @preconcurrency NetServiceDelegate {
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        let id = key(service)
        resolving[id] = service
        service.delegate = self
        service.resolve(withTimeout: 5)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        let id = key(service)
        resolving.removeValue(forKey: id)?.stop()
        services.removeAll { $0.id == id }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        errorMessage = "Bonjour search failed: \(errorDict). Check local network access in System Settings."
        self.browser = nil
        isBrowsing = false
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let host = sender.hostName, (1...65535).contains(sender.port) else { return }
        let id = key(sender)
        let txt = sender.txtRecordData().map(NetService.dictionary(fromTXTRecord:)) ?? [:]
        let role = txt["role"].flatMap { String(data: $0, encoding: .utf8) }
        services.removeAll { $0.id == id }
        services.append(Service(id: id, name: sender.name, host: host, port: sender.port, isReceiver: role == "receiver"))
        services.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        errorMessage = "Could not resolve \(sender.name): \(errorDict)"
    }

    func netServiceDidPublish(_ sender: NetService) {
        if sender === advertisement { isAdvertising = true }
    }

    func netService(_ sender: NetService, didNotPublish errorDict: [String: NSNumber]) {
        errorMessage = "Bonjour announcement failed: \(errorDict)"
        stopAdvertising()
    }
}

struct SRTNetworkControls: View {
    @ObservedObject var discovery: SRTBonjourDiscovery
    let receiving: Bool
    let busy: Bool
    let connect: (URL) -> Void
    let listen: (Int) -> Void
    @State private var port = "9000"

    var body: some View {
        StudioSection(title: "SRT on your network", subtitle: "Discover a source or receive directly") {
            Button(discovery.isBrowsing ? "Refresh services" : "Find Bonjour services") {
                discovery.stop()
                discovery.startBrowsing()
            }.disabled(receiving || busy)
            if discovery.isBrowsing && discovery.services.isEmpty {
                Text("Looking for _srt._udp services…").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(discovery.services.filter { !$0.isReceiver }) { service in
                Button {
                    if let url = service.url { connect(url) }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(service.name, systemImage: "network")
                        Text("\(service.host):\(service.port)").font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.disabled(receiving || busy)
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text("Receive port").font(.callout.weight(.medium))
                TextField("9000", text: $port)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Receive port")
                    .disabled(receiving || busy)
            }
            Button("Listen for SRT sender") {
                if let port = Int(port), (1...65535).contains(port) { listen(port) }
            }
            .disabled(receiving || busy || Int(port).map { !(1...65535).contains($0) } ?? true)
            if discovery.isAdvertising {
                Label("Receiver announced on Bonjour", systemImage: "dot.radiowaves.left.and.right")
                    .font(.callout)
            }
            if let error = discovery.errorMessage {
                Text(error).font(.callout).foregroundStyle(.red)
            }
            Text("Only services advertising _srt._udp appear here. Listener mode accepts one sender; the sender must use SRT caller mode.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }
}
