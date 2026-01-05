import HaishinKit
@preconcurrency import Logboard
import RTCHaishinKit
import RTMPHaishinKit
import SRTHaishinKit
import SwiftUI

nonisolated let logger = LBLogger.with("com.haishinkit.HaishinApp")

@main
struct HaishinApp: App {
    @State private var preference = PreferenceViewModel()
    @State private var isInitialized = false

    var body: some Scene {
        WindowGroup {
            if isInitialized {
                ContentView()
                    .environmentObject(preference)
            } else {
                LaunchScreen()
                    .task {
                        await initialize()
                        isInitialized = true
                    }
            }
        }
    }

    private func initialize() async {
        await SessionBuilderFactory.shared.register(RTMPSessionFactory())
        await SessionBuilderFactory.shared.register(SRTSessionFactory())
        await SessionBuilderFactory.shared.register(HTTPSessionFactory())

        await RTCLogger.shared.setLevel(.debug)
        await SRTLogger.shared.setLevel(.debug)
    }

    init() {
        LBLogger(kHaishinKitIdentifier).level = .debug
        LBLogger(kRTCHaishinKitIdentifier).level = .debug
        LBLogger(kRTMPHaishinKitIdentifier).level = .debug
        LBLogger(kSRTHaishinKitIdentifier).level = .debug
    }
}

struct LaunchScreen: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "video.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.white)
                Text("HaishinKit")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                ProgressView()
                    .tint(.white)
                    .padding(.top, 20)
            }
        }
    }
}
