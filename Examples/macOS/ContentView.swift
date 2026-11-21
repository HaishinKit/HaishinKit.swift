import SwiftUI

struct ContentView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case playback = "Playback"
        case publish = "Publish"
        case settings = "Settings"
        case debug = "Debug"

        var id: Self { self }
        var icon: String {
            switch self {
            case .playback: return "play.rectangle"
            case .publish: return "dot.radiowaves.left.and.right"
            case .settings: return "slider.horizontal.3"
            case .debug: return "ladybug"
            }
        }
    }

    @State private var selection: Tab? = .playback

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "waveform.path")
                        .font(.title2).foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("HaishinKit").font(.headline)
                        Text("Development console").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(20)
                List(selection: $selection) {
                    Section("Workspace") {
                        ForEach([Tab.playback, .publish]) { tab in
                            Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                        }
                    }
                    Section("Configuration") {
                        Label(Tab.settings.rawValue, systemImage: Tab.settings.icon).tag(Tab.settings)
                        Label(Tab.debug.rawValue, systemImage: Tab.debug.icon).tag(Tab.debug)
                    }
                }
                .listStyle(.sidebar)
                Text("macOS Example")
                    .font(.caption).foregroundStyle(.secondary).padding(20)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 250)
        } detail: {
            switch selection ?? .playback {
            case .playback: PlaybackView()
            case .publish: PublishView()
            case .settings: MacSettingsView()
            case .debug: DebugView()
            }
        }
        .frame(minWidth: 900, minHeight: 620)
        .tint(.accentColor)
    }
}
