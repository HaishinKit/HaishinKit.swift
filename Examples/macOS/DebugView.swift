import HaishinKit
@preconcurrency import Logboard
import RTCHaishinKit
import RTMPHaishinKit
import SRTHaishinKit
import SwiftUI

struct DebugView: View {
    @EnvironmentObject private var preference: PreferenceViewModel
    @AppStorage("macos.debug.verboseLogging") private var verboseLogging = true
    @Binding var appearance: String
    @State private var serverHost = "127.0.0.1"
    @State private var serverPort = "8889"
    @State private var streamPath = "live"
    @State private var presetMessage: String?

    private func endpoint(_ operation: String) -> URL? {
        guard !serverHost.isEmpty, !streamPath.isEmpty,
              let port = Int(serverPort), (1...65535).contains(port) else { return nil }
        var components = URLComponents()
        components.scheme = "http"
        components.host = serverHost
        components.port = port
        components.path = "/\(streamPath)/\(operation)"
        return components.url
    }

    var body: some View {
        Form {
            Section {
                Picker(String(localized: "Appearance"), selection: $appearance) {
                    Text(String(localized: "System")).tag("system")
                    Text(String(localized: "Light")).tag("light")
                    Text(String(localized: "Dark")).tag("dark")
                }
                Text(String(localized: "Appearance overrides apply until the app closes. Each launch follows the system setting."))
                    .font(.caption).foregroundStyle(.secondary)
                Toggle(String(localized: "Verbose logging"), isOn: $verboseLogging)
                    .onChange(of: verboseLogging) { _, value in
                        let level: LBLogger.Level = value ? .debug : .warn
                        LBLogger(kHaishinKitIdentifier).level = level
                        LBLogger(kRTMPHaishinKitIdentifier).level = level
                        LBLogger(kSRTHaishinKitIdentifier).level = level
                        LBLogger(kRTCHaishinKitIdentifier).level = level
                        Task {
                            await RTCLogger.shared.setLevel(value ? .debug : .warning)
                            await SRTLogger.shared.setLevel(value ? .debug : .warning)
                        }
                    }
                Text(String(localized: "Inspect library logs in Xcode or Console. Debug logs may contain endpoint URLs or signaling data."))
                    .foregroundStyle(.secondary)
            } header: {
                Text(String(localized: "Diagnostics"))
            }
            Section {
                Button(String(localized: "Open publish memory-release test")) { preference.showPublishSheet = true }
                Text(String(localized: "Open and dismiss the publisher repeatedly while inspecting memory in Instruments. Dismissing closes capture and network sessions."))
                    .foregroundStyle(.secondary)
            } header: {
                Text(String(localized: "Lifecycle"))
            }
            Section {
                TextField(String(localized: "Server host"), text: $serverHost)
                TextField(String(localized: "HTTP port"), text: $serverPort)
                TextField(String(localized: "Stream path"), text: $streamPath)
                HStack {
                    Button(String(localized: "Use WHIP endpoint")) { applyPreset("whip") }
                    Button(String(localized: "Use WHEP endpoint")) { applyPreset("whep") }
                }
                .disabled(endpoint("whip") == nil)
                if let presetMessage { Text(presetMessage).foregroundStyle(.secondary).textSelection(.enabled) }
                Text(String(localized: "Run MediaMTX separately. These presets configure a client endpoint; they do not start a server. Use Opus audio when publishing with WHIP."))
                    .foregroundStyle(.secondary)
                Link(String(localized: "MediaMTX setup and supported protocols"), destination: URL(string: "https://mediamtx.org/docs/features/publish-and-read")!)
            } header: {
                Text(String(localized: "WHIP / WHEP test server"))
            }
            Section(String(localized: "Environment")) {
                LabeledContent(String(localized: "App version"), value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                LabeledContent(String(localized: "Operating system"), value: ProcessInfo.processInfo.operatingSystemVersionString)
                LabeledContent(String(localized: "SRT library"), value: SRTConnection.version)
                LabeledContent(String(localized: "Bonjour service"), value: "_srt._udp")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(String(localized: "Debug"))
        .sheet(isPresented: $preference.showPublishSheet) {
            VStack(spacing: 0) {
                HStack {
                    Text(String(localized: "Publish lifecycle test")).font(.headline)
                    Spacer()
                    Button(String(localized: "Close")) { preference.showPublishSheet = false }
                        .keyboardShortcut(.cancelAction)
                }.padding()
                Divider()
                PublishView()
            }
            .frame(width: 1000, height: 700)
        }
    }

    private func applyPreset(_ operation: String) {
        guard let url = endpoint(operation) else { return }
        preference.uri = url.absoluteString
        if operation == "whip" { preference.audioFormat = .opus }
        presetMessage = String(localized: "Next session: \(url.absoluteString)")
    }
}
