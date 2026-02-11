import Foundation
import HaishinKit

public struct SRTSessionFactory: StreamSessionFactory {
    public let supportedProtocols: Set<String> = ["srt"]

    public init() {
    }

    public func make(_ uri: URL, mode: StreamSessionMode, configuration: (any StreamSessionConfiguration)?) -> any StreamSession {
        return SRTSession(uri: uri, mode: mode, configuration: configuration)
    }
}
