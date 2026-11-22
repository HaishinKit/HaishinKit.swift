import Combine
import Foundation
import UIKit

@MainActor
final class TVBonjourDiscovery: NSObject, ObservableObject {
    enum Role: String { case receiver, source }
    struct Service: Identifiable {
        let id: String
        let name: String
        let host: String
        let port: Int
        let role: Role
        var url: URL? {
            var parts = URLComponents()
            parts.scheme = "srt"
            parts.host = host
            parts.port = port
            parts.queryItems = [.init(name: "mode", value: "caller")]
            return parts.url
        }
    }
    @Published private(set) var services: [Service] = []
    @Published private(set) var isBrowsing = false
    @Published private(set) var isAdvertising = false
    @Published private(set) var errorMessage: String?
    private var browser: NetServiceBrowser?
    private var pending: [String: NetService] = [:]
    private var advertisement: NetService?

    func browse() {
        stopBrowsing()
        errorMessage = nil
        let browser = NetServiceBrowser()
        self.browser = browser
        browser.delegate = self
        isBrowsing = true
        browser.searchForServices(ofType: "_srt._udp.", inDomain: "local.")
    }

    func advertise(port: Int, role: Role) {
        stopAdvertising()
        errorMessage = nil
        let service = NetService(
            domain: "local.", type: "_srt._udp.",
            name: "HaishinKit \(role == .receiver ? "Receiver" : "Source") – \(UIDevice.current.name)", port: Int32(port))
        advertisement = service
        service.delegate = self
        service.setTXTRecord(NetService.data(fromTXTRecord: ["role": Data(role.rawValue.utf8), "version": Data("1".utf8)]))
        service.publish()
    }

    func stopAdvertising() {
        advertisement?.delegate = nil
        advertisement?.stop()
        advertisement = nil
        isAdvertising = false
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
        services.removeAll()
        isBrowsing = false
    }

    private func key(_ service: NetService) -> String { "\(service.domain)/\(service.type)/\(service.name)" }
}

extension TVBonjourDiscovery: @preconcurrency NetServiceBrowserDelegate, @preconcurrency NetServiceDelegate {
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        guard browser === self.browser else { return }
        let id = key(service)
        pending[id]?.stop()
        services.removeAll { $0.id == id }
        pending[id] = service
        service.delegate = self
        service.resolve(withTimeout: 5)
    }
    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        guard browser === self.browser else { return }
        let id = key(service)
        pending.removeValue(forKey: id)?.stop()
        services.removeAll { $0.id == id }
    }
    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        guard browser === self.browser else { return }
        stopBrowsing()
        errorMessage = "Bonjour search failed. Check Local Network access in Settings, then try again."
    }
    func netServiceDidResolveAddress(_ sender: NetService) {
        let id = key(sender)
        guard pending[id] === sender else { return }
        pending.removeValue(forKey: id)
        guard sender.name != advertisement?.name, let host = sender.hostName, (1...65535).contains(sender.port) else { return }
        let txt = sender.txtRecordData().map(NetService.dictionary(fromTXTRecord:)) ?? [:]
        guard let value = txt["role"].flatMap({ String(data: $0, encoding: .utf8) }), let role = Role(rawValue: value) else { return }
        services.removeAll { $0.id == id }
        services.append(.init(id: id, name: sender.name, host: host, port: sender.port, role: role))
        services.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        guard pending[key(sender)] === sender else { return }
        pending.removeValue(forKey: key(sender))
        errorMessage = "A receiver could not be resolved. Refresh to try again."
    }
    func netServiceDidPublish(_ sender: NetService) {
        guard sender === advertisement else { return }
        isAdvertising = true
        services.removeAll { $0.name == sender.name }
    }
    func netService(_ sender: NetService, didNotPublish errorDict: [String: NSNumber]) {
        guard sender === advertisement else { return }
        stopAdvertising()
        errorMessage = "Bonjour announcement failed. You can still connect using this Apple TV's address and port."
    }
}
