import HaishinKit
@preconcurrency import Logboard
import RTCHaishinKit
import RTMPHaishinKit
import SRTHaishinKit
import SwiftUI

let logger = LBLogger.with("com.haishinkit.HaishinKit.HaishinApp")

@main
struct HaishinApp: App {
    @AppStorage("macos.debug.appearance") private var appearance = "system"
    @StateObject private var preference = PreferenceViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(preference)
                .preferredColorScheme(appearance == "light" ? .light : (appearance == "dark" ? .dark : nil))
        }
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)
    }

    init() {
        let verbose = UserDefaults.standard.object(forKey: "macos.debug.verboseLogging") as? Bool ?? true
        Task {
            await StreamSessionBuilderFactory.shared.register(RTMPSessionFactory())
            await StreamSessionBuilderFactory.shared.register(SRTSessionFactory())
            await StreamSessionBuilderFactory.shared.register(HTTPSessionFactory())

            await RTCLogger.shared.setLevel(verbose ? .debug : .warning)
            await SRTLogger.shared.setLevel(verbose ? .debug : .warning)
        }
        let level: LBLogger.Level = verbose ? .debug : .warn
        LBLogger(kHaishinKitIdentifier).level = level
        LBLogger(kSRTHaishinKitIdentifier).level = level
        LBLogger(kRTCHaishinKitIdentifier).level = level
        LBLogger(kRTMPHaishinKitIdentifier).level = level
    }
}
