import Foundation

nonisolated enum VisionStudioEndpoint {
    static func make(server: String, streamName: String) -> URL? {
        let input = server.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var parts = URLComponents(string: input), let scheme = parts.scheme?.lowercased(),
              let host = parts.host, !host.isEmpty, parts.url != nil, parts.fragment == nil else { return nil }
        parts.scheme = scheme
        if parts.rangeOfPort != nil {
            guard let port = parts.port, (1...65535).contains(port) else { return nil }
        }
        switch scheme {
        case "rtmp", "rtmps":
            let name = streamName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty,
                  let key = URLComponents(string: "rtmp://stream.invalid/" + name),
                  key.fragment == nil, key.path != "/" else { return nil }
            guard !parts.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).isEmpty else { return nil }
            // The stream name can carry a signed query. Keep it as a query, not an
            // escaped part of the path. Server query items precede stream query items.
            parts.path = parts.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + key.path
            if !parts.path.hasPrefix("/") { parts.path = "/" + parts.path }
            let queries = [parts.percentEncodedQuery, key.percentEncodedQuery].compactMap { $0 }.filter { !$0.isEmpty }
            parts.percentEncodedQuery = queries.isEmpty ? nil : queries.joined(separator: "&")
            return parts.url
        case "srt":
            guard parts.port != nil else { return nil }
            let modes = parts.queryItems?.filter { $0.name == "mode" } ?? []
            guard modes.count <= 1,
                  modes.allSatisfy({ $0.value == "caller" || $0.value == "client" }),
                  !(parts.queryItems?.contains { $0.name == "adapter" } ?? false) else { return nil }
            // Empty queries crash the transport's legacy query parser. Always supply
            // the explicit caller mode; listener/rendezvous belong to the tvOS studio.
            if modes.isEmpty {
                parts.queryItems = (parts.queryItems ?? []) + [URLQueryItem(name: "mode", value: "caller")]
            }
            return parts.url
        default: return nil
        }
    }
}
