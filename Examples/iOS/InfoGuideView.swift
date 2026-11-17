import SwiftUI

private enum InfoTab: String, CaseIterable {
    case preference = "Preference"
    case publish = "Publish"
}

struct InfoGuideView: View {
    @Binding var showingInfo: Bool
    @State private var selectedTab: InfoTab = .preference

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("", selection: $selectedTab) {
                    ForEach(InfoTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                .padding(.top, 8)

                TabView(selection: $selectedTab) {
                    PreferenceGuideList()
                        .tag(InfoTab.preference)
                    PublishGuideList()
                        .tag(InfoTab.publish)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationTitle("Help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { showingInfo = false }
                }
            }
        }
    }
}

private struct PreferenceGuideList: View {
    var body: some View {
        List {
            Section("Stream Settings") {
                GuideRow(title: "URL", description: "RTMP server address (e.g., rtmp://your-server.com/live)")
                GuideRow(title: "Stream Name", description: "Unique stream key provided by your streaming platform")
            }
            Section("Audio Settings") {
                GuideRow(title: "Format", description: "AAC: Universal compatibility\nOpus: Better quality at low bitrates")
            }
            Section("Video Settings") {
                GuideRow(title: "HDR Video", description: "Captures wider color/brightness range. Requires HDR-capable camera.")
                GuideRow(title: "Low Latency", description: "Reduces stream delay to ~2-3 seconds. May slightly reduce quality.")
                GuideRow(title: "Resolution", description: "Choose 720p for performance or 1080p for higher detail.")
                GuideRow(title: "BitRate Mode", description: "Average: Consistent file size\nConstant: Stable quality\nVariable: Best quality")
            }
            Section("Capture Settings") {
                GuideRow(title: "Preview Type", description: "Metal: Fast GPU-based preview.\nSystem PiP: Enables background streaming. When you switch apps, receive a phone call, or go to home screen, your stream continues in a floating window instead of dying.")
                GuideRow(title: "Audio Capture", description: "AudioEngine: Most stable\nAudioSource: Direct capture\nStereo: For external mics")
                GuideRow(title: "GPU Rendering", description: "Uses GPU for video effects. Disable if experiencing issues.")
            }
            Section("Debug") {
                GuideRow(title: "Memory Release Test", description: "Opens PublishView in a sheet to verify memory is properly released when dismissed to help detect memory leaks.")
            }
        }
    }
}

private struct PublishGuideList: View {
    var body: some View {
        List {
            Section("Stream Settings") {
                GuideRowWithIcon(icon: "15", isText: true, title: "FPS",
                                 description: "Frames per second. 15 saves battery, 30 is standard, 60 is ultra-smooth.")
                GuideRowWithIcon(icon: "slider.horizontal.3", title: "Bitrate (kbps)",
                                 description: "Video quality. Higher = better but more data. 1500-2500 recommended.")
                GuideRowWithIcon(icon: "rectangle.badge.checkmark", title: "720p / 1080p",
                                 description: "Video resolution. 720p = lighter load, 1080p = sharper image but needs more CPU/network.")
            }
            Section("Controls") {
                GuideRowWithIcon(icon: "record.circle", title: "Record",
                                 description: "Save a local copy to Photos. Only available while streaming.")
                GuideRowWithIcon(icon: "mic.fill", title: "Mute",
                                 description: "Mute/unmute microphone. Red when muted.")
                GuideRowWithIcon(icon: "arrow.triangle.2.circlepath.camera", title: "Flip Camera",
                                 description: "Switch between front and back cameras.")
                GuideRowWithIcon(icon: "flashlight.on.fill", title: "Torch",
                                 description: "Toggle flashlight. Only works with back camera.")
                GuideRowWithIcon(icon: "rectangle.on.rectangle", title: "Dual Camera",
                                 description: "Overlay the other camera in your stream. Viewers see both cameras.")
            }
            Section("Live Stats") {
                GuideRowWithIcon(icon: "arrow.up", title: "Upload Speed",
                                 description: "Current upload rate in KB/s. The graph shows last 60 seconds.")
                GuideRowWithIcon(icon: "thermometer.medium", title: "Temperature",
                                 description: "Device thermal state. Lower FPS/bitrate if too hot.")
            }
        }
    }
}

private struct GuideRow: View {
    let title: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct GuideRowWithIcon: View {
    let icon: String
    var isText: Bool = false
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if isText {
                Text(icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.cyan)
                    .frame(width: 28, height: 28)
                    .background(Color.cyan.opacity(0.2))
                    .cornerRadius(6)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(.cyan)
                    .frame(width: 28, height: 28)
                    .background(Color.cyan.opacity(0.2))
                    .cornerRadius(6)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
