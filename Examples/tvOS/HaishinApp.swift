import HaishinKit
@preconcurrency import Logboard
import RTCHaishinKit
import RTMPHaishinKit
import SRTHaishinKit
import SwiftUI

let logger = LBLogger.with("com.haishinkit.HaishinKit.HaishinApp")

@main
struct HaishinApp: App {
    @StateObject private var preference = PreferenceViewModel()
    @StateObject private var studio = TVStudioModel()

    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(preference).environmentObject(studio)
        }
    }

    init() {
        Task {
            await StreamSessionBuilderFactory.shared.register(RTMPSessionFactory())
            await StreamSessionBuilderFactory.shared.register(SRTSessionFactory())
            await StreamSessionBuilderFactory.shared.register(HTTPSessionFactory())

            await RTCLogger.shared.setLevel(.debug)
            await SRTLogger.shared.setLevel(.debug)
        }
        LBLogger(kHaishinKitIdentifier).level = .debug
        LBLogger(kRTCHaishinKitIdentifier).level = .debug
        LBLogger(kRTMPHaishinKitIdentifier).level = .debug
        LBLogger(kSRTHaishinKitIdentifier).level = .debug
    }
}
