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
    }

    init() {
        Task {
            await StreamSessionBuilderFactory.shared.register(RTMPSessionFactory())
            await StreamSessionBuilderFactory.shared.register(SRTSessionFactory())
        }
    }
}
