import Combine
import Foundation
import HaishinKit
import libsrt

struct SRTSocketURL {
    static let defaultPort: Int = 9710

    private static func getQueryItems(_ url: URL) -> [String: String] {
        let url = url.absoluteString
        if !url.contains("?") {
            return [:]
        }
        let queryString = url.split(separator: "?")[1]
        let queries = queryString.split(separator: "&")
        var paramsReturn: [String: String] = [:]
        for q in queries {
            let query = q.split(separator: "=", maxSplits: 1)
            if query.count == 2 {
                paramsReturn[String(query[0])] = String(query[1])
            }
        }
        return paramsReturn
    }

    let url: URL
    let mode: SRTMode
    let options: [SRTSocketOption]

    var remote: AddrInfo? {
        guard let host = url.host else {
            return nil
        }
        return AddrInfo(host: host, port: url.port ?? Self.defaultPort)
    }

    var local: AddrInfo? {
        let queryItems = Self.getQueryItems(url)
        let adapter = queryItems["adapter"] ?? "0.0.0.0"
        if let port = queryItems["port"] {
            return AddrInfo(host: adapter, port: Int(port) ?? url.port ?? Self.defaultPort)
        }
        return AddrInfo(host: adapter, port: url.port ?? Self.defaultPort)
    }

    init?(_ url: URL?) {
        guard let url, let scheme = url.scheme, scheme == "srt" else {
            return nil
        }
        let queryItems = Self.getQueryItems(url)
        var options: [SRTSocketOption] = []
        for item in queryItems {
            guard let name = SRTSocketOption.Name(rawValue: item.key) else {
                continue
            }
            if let option = try? SRTSocketOption(name: name, value: item.value) {
                options.append(option)
            }
        }
        self.url = url
        self.mode = {
            switch queryItems["mode"] {
            case "client", "caller":
                return .caller
            case "server", "listener":
                return .listener
            case "rendezvous":
                return .rendezvous
            default:
                if queryItems["adapter"] != nil {
                    return .rendezvous
                }
                if url.host?.isEmpty == true {
                    return .listener
                }
                return .caller
            }
        }()
        self.options = options
    }
}
