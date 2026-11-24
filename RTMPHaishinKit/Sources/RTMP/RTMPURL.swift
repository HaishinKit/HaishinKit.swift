import Foundation

struct RTMPURL {
    let url: URL

    var streamName: String {
        let pathComponents = url.pathComponents.dropFirst(2)
        if let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery {
            return pathComponents.joined(separator: "/") + "?" + query
        } else {
            return pathComponents.joined(separator: "/")
        }
    }

    var command: String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        // An RTMP URL's first path component is the application; the remaining
        // path and encoded query are the stream name. Never search in the host.
        let application = components.percentEncodedPath.split(separator: "/").first
        components.percentEncodedPath = application.map { "/" + $0 } ?? ""
        components.percentEncodedQuery = nil
        components.fragment = nil
        return components.url?.absoluteString ?? url.absoluteString
    }

    init(url: URL) {
        self.url = url
    }
}
