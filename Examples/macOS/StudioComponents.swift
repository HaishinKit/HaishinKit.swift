import AVFoundation
import HaishinKit
import SwiftUI

struct SessionStatus: View {
    let state: StreamSessionReadyState
    var busy = false
    var publishing = false
    var waiting = false

    var title: String {
        if waiting { return String(localized: "Waiting for sender") }
        if busy { return state == .open ? String(localized: "Stopping…") : String(localized: "Connecting…") }
        switch state {
        case .open: return publishing ? String(localized: "Live") : String(localized: "Playing")
        case .connecting: return String(localized: "Connecting…")
        case .closing: return String(localized: "Stopping…")
        case .closed: return String(localized: "Standby")
        }
    }

    var body: some View {
        Label {
            Text(title).foregroundStyle(.primary)
        } icon: {
            Image(systemName: state == .open ? "dot.radiowaves.left.and.right" : "circle.fill")
                .foregroundStyle(state == .open ? Color.green : Color.secondary)
        }
            .font(.callout.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.quaternary, in: Capsule())
            .accessibilityLabel(String(localized: "Session status: \(title)"))
    }
}

struct StudioSection<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator.opacity(0.5)))
    }
}

struct ConnectionFields: View {
    @EnvironmentObject private var preference: PreferenceViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "Server URL")).font(.callout.weight(.medium))
                TextField("rtmp://localhost/live", text: $preference.uri)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(String(localized: "Server URL"))
            }
            if preference.uri.lowercased().hasPrefix("rtmp://") || preference.uri.lowercased().hasPrefix("rtmps://") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "Stream name / key")).font(.callout.weight(.medium))
                    SecureField(String(localized: "Stream name or key"), text: $preference.streamName)
                        .textFieldStyle(.roundedBorder)
                }
            }
            Text(String(localized: "Use the endpoint provided by your streaming server."))
                .font(.callout).foregroundStyle(.secondary)
        }
    }
}

struct StudioEmptyState: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 36, weight: .light)).accessibilityHidden(true)
            Text(title).font(.title3.weight(.semibold))
            Text(subtitle).font(.callout).multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.75)).frame(maxWidth: 300)
        }
        .foregroundStyle(.white)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
    }
}

struct MacSettingsView: View {
    @AppStorage("macos.capture.microphoneEnabled") private var microphoneEnabled = false
    @State private var microphoneAccess = AVCaptureDevice.authorizationStatus(for: .audio)
    @EnvironmentObject private var preference: PreferenceViewModel

    var body: some View {
        Form {
            Section(String(localized: "Connection")) {
                ConnectionFields()
            }
            Section {
                Picker(String(localized: "Audio format"), selection: $preference.audioFormat) {
                    ForEach(AudioCodecSettings.Format.allCases, id: \.self) { format in
                        Text(String(describing: format).uppercased()).tag(format)
                    }
                }
                Picker(String(localized: "Bitrate mode"), selection: $preference.bitRateMode) {
                    ForEach(preference.bitRateModes, id: \.description) { mode in
                        Text(mode.description).tag(mode)
                    }
                }
                Toggle(String(localized: "Low latency"), isOn: $preference.isLowLatencyRateControlEnabled)
            } header: {
                Text(String(localized: "Publishing"))
            } footer: {
                Text(String(localized: "Changes apply to the next session. AAC and average bitrate are a good starting point."))
            }
            Section(String(localized: "Capture")) {
                Toggle(String(localized: "Enable microphone"), isOn: $microphoneEnabled)
                if microphoneEnabled && microphoneAccess != .authorized {
                    Button(String(localized: "Request microphone access")) {
                        Task {
                            _ = await AVCaptureDevice.requestAccess(for: .audio)
                            microphoneAccess = AVCaptureDevice.authorizationStatus(for: .audio)
                        }
                    }
                    Text(String(localized: "If access was denied, enable this app in System Settings → Privacy & Security → Microphone."))
                        .foregroundStyle(.secondary)
                }
                Picker(String(localized: "Microphone capture"), selection: Binding(
                    get: { preference.audioCaptureMode == .audioEngine },
                    set: { preference.audioCaptureMode = $0 ? .audioEngine : .audioSource }
                )) {
                    Text(String(localized: "Audio Engine (recommended)")).tag(true)
                    Text("AVCaptureSession").tag(false)
                }
                Text(String(localized: "Applied when the publisher opens. Audio Engine keeps microphone input separate from camera capture."))
                    .foregroundStyle(.secondary)
            }
            Section { UpdateSettingsView() }
            Section(String(localized: "About")) {

                LabeledContent(String(localized: "Library"), value: "HaishinKit.swift")
                LabeledContent(String(localized: "Platform"), value: "macOS · Apple Silicon")
                Link(String(localized: "API documentation"), destination: URL(string: "https://docs.haishinkit.com/swift/latest/documentation/")!)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(String(localized: "Settings"))
    }
}
