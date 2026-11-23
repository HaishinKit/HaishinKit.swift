import Sparkle
import SwiftUI

@MainActor
final class AppUpdater: ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var automaticallyDownloadsUpdates = false
    private let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    init() {
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates).assign(to: &$automaticallyChecksForUpdates)
        controller.updater.publisher(for: \.automaticallyDownloadsUpdates).assign(to: &$automaticallyDownloadsUpdates)
    }

    func checkForUpdates() { controller.checkForUpdates(nil) }
    func setAutomaticallyChecksForUpdates(_ value: Bool) { controller.updater.automaticallyChecksForUpdates = value }
    func setAutomaticallyDownloadsUpdates(_ value: Bool) { controller.updater.automaticallyDownloadsUpdates = value }
}

struct CheckForUpdatesButton: View {
    @ObservedObject var updater: AppUpdater
    var body: some View {
        Button(String(localized: "Check for Updates…"), action: updater.checkForUpdates)
            .disabled(!updater.canCheckForUpdates)
    }
}

struct UpdateSettingsView: View {
    @EnvironmentObject private var updater: AppUpdater
    var body: some View {
        StudioSection(title: String(localized: "App updates"), subtitle: String(localized: "Updates from GitHub Releases")) {
            Toggle(String(localized: "Automatically check for updates"), isOn: Binding(
                get: { updater.automaticallyChecksForUpdates }, set: updater.setAutomaticallyChecksForUpdates))
            Toggle(String(localized: "Download and install updates automatically"), isOn: Binding(
                get: { updater.automaticallyDownloadsUpdates }, set: updater.setAutomaticallyDownloadsUpdates))
                .disabled(!updater.automaticallyChecksForUpdates)
            CheckForUpdatesButton(updater: updater)
            Text(String(localized: "Updates are verified before installation. Restart when you are ready to finish your current session."))
                .font(.callout).foregroundStyle(.secondary)
        }
    }
}
