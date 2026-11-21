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
                Picker("Appearance", selection: $appearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                Text("Appearance overrides apply until the app closes. Each launch follows the system setting.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Verbose logging", isOn: $verboseLogging)
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
                Text("Inspect library logs in Xcode or Console. Debug logs may contain endpoint URLs or signaling data.")
                    .foregroundStyle(.secondary)
            } header: {
                Text("Diagnostics")
            }
            Section {
                Button("Open publish memory-release test") { preference.showPublishSheet = true }
                Text("Open and dismiss the publisher repeatedly while inspecting memory in Instruments. Dismissing closes capture and network sessions.")
                    .foregroundStyle(.secondary)
            } header: {
                Text("Lifecycle")
            }
            Section {
                TextField("Server host", text: $serverHost)
                TextField("HTTP port", text: $serverPort)
                TextField("Stream path", text: $streamPath)
                HStack {
                    Button("Use WHIP endpoint") { applyPreset("whip") }
                    Button("Use WHEP endpoint") { applyPreset("whep") }
                }
                .disabled(endpoint("whip") == nil)
                if let presetMessage { Text(presetMessage).foregroundStyle(.secondary).textSelection(.enabled) }
                Text("Run MediaMTX separately. These presets configure a client endpoint; they do not start a server. Use Opus audio when publishing with WHIP.")
                    .foregroundStyle(.secondary)
                Link("MediaMTX setup and supported protocols", destination: URL(string: "https://mediamtx.org/docs/features/publish-and-read")!)
            } header: {
                Text("WHIP / WHEP test server")
            }
            Section("Environment") {
                LabeledContent("App version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                LabeledContent("Operating system", value: ProcessInfo.processInfo.operatingSystemVersionString)
                LabeledContent("SRT library", value: SRTConnection.version)
                LabeledContent("Bonjour service", value: "_srt._udp")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Debug")
        .sheet(isPresented: $preference.showPublishSheet) {
            VStack(spacing: 0) {
                HStack {
                    Text("Publish lifecycle test").font(.headline)
                    Spacer()
                    Button("Close") { preference.showPublishSheet = false }
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
        presetMessage = "Next session: \(url.absoluteString)"
    }
}
