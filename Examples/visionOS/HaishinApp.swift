import HaishinKit
@preconcurrency import Logboard
import RTMPHaishinKit
import SRTHaishinKit
import SwiftUI

let logger = LBLogger.with("com.haishinkit.HaishinKit.visionOSApp")

@main
struct HaishinApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 1100, height: 760)
        .windowResizability(.contentMinSize)
    }

    init() {
        // Logboard's logger cache is not synchronized. Populate it before media tasks
        // can initialize the transport and mixer loggers concurrently.
        for identifier in [kHaishinKitIdentifier, kRTMPHaishinKitIdentifier, kSRTHaishinKitIdentifier,
                           "com.haishinkit.HaishinKit.visionOSApp"] {
            _ = LBLogger.with(identifier)
        }
        Task {
            await StreamSessionBuilderFactory.shared.register(RTMPSessionFactory())
            await StreamSessionBuilderFactory.shared.register(SRTSessionFactory())
        }
    }
}
