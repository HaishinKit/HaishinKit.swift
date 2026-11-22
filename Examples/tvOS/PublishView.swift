import SwiftUI

/// An independent studio for the shared settings screen's lifecycle test.
struct PublishView: View {
    @StateObject private var studio = TVStudioModel()

    var body: some View {
        ContentView()
            .environmentObject(studio)
            .task { await studio.selectDirection(.send) }
            .onDisappear { Task { await studio.shutdown() } }
    }
}
