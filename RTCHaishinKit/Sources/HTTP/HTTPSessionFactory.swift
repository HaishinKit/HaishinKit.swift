import Foundation
import HaishinKit

public struct HTTPSessionFactory: StreamSessionFactory {
    public let supportedProtocols: Set<String> = ["http", "https"]

    public init() {
    }

    public func make(_ uri: URL, mode: StreamSessionMode, configuration: (any StreamSessionConfiguration)?) -> any StreamSession {
        return HTTPSession(uri: uri, mode: mode, configuration: configuration)
    }
}
