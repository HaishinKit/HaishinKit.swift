import SwiftUI

struct SceneOpenRequest: Equatable {
    let id = UUID()
    let url: URL
}

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

    @Binding var appearance: String

    @State private var selection: Tab? = .playback
    @State private var sceneOpenRequest: SceneOpenRequest?

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "waveform.path")
                        .font(.title2).foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("HaishinKit").font(.headline)
                        Text(String(localized: "Development console")).font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(20)
                List(selection: $selection) {
                    Section(String(localized: "Workspace")) {
                        ForEach([Tab.playback, .publish]) { tab in
                            Label(LocalizedStringKey(tab.rawValue), systemImage: tab.icon).tag(tab)
                        }
                    }
                    Section(String(localized: "Configuration")) {
                        Label(LocalizedStringKey(Tab.settings.rawValue), systemImage: Tab.settings.icon).tag(Tab.settings)
                        Label(LocalizedStringKey(Tab.debug.rawValue), systemImage: Tab.debug.icon).tag(Tab.debug)
                    }
                }
                .listStyle(.sidebar)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 250)
        } detail: {
            switch selection ?? .playback {
            case .playback: PlaybackView()
            case .publish: PublishView(sceneOpenRequest: $sceneOpenRequest)
            case .settings: MacSettingsView()
            case .debug: DebugView(appearance: $appearance)
            }
        }
        .frame(minWidth: 900, minHeight: 620)
        .tint(.accentColor)
        .onOpenURL { url in
            guard url.isFileURL, ["scene", "json"].contains(url.pathExtension.lowercased()) else { return }
            sceneOpenRequest = SceneOpenRequest(url: url)
            selection = .publish
        }
    }
}
