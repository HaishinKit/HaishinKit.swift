import Foundation
import HaishinKit

public struct RTMPSessionFactory: StreamSessionFactory {
    public let supportedProtocols: Set<String> = ["rtmp", "rtmps"]

    public init() {
    }

    public func make(_ uri: URL, mode: StreamSessionMode, configuration: (any StreamSessionConfiguration)?) -> any StreamSession {
        return RTMPSession(uri: uri, mode: mode, configuration: configuration)
    }
}
