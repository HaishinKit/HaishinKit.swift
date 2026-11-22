import AVKit
import HaishinKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var studio: TVStudioModel
    @EnvironmentObject private var preference: PreferenceViewModel
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var qualityClient = TVQualityClient()
    @State private var showQuality = false
    @State private var showCameraPicker = false
    @State private var showLegacy = false
    @State private var fullScreen = false

    var body: some View {
        ZStack {
            Color.clear.ignoresSafeArea()
            if fullScreen {
                TVVideoPreview(studio: studio).ignoresSafeArea()
                    .overlay(alignment: .bottom) {
                        HStack(spacing: 28) {
                            Button("Back to controls", systemImage: "arrow.down.right.and.arrow.up.left") { fullScreen = false }
                            if studio.isActive { Button("Stop", systemImage: "stop.fill") { Task { await studio.stop() } } }
                        }.padding(40).background(.thinMaterial)
                    }
                    .onExitCommand { fullScreen = false }
            } else {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    HStack(alignment: .top, spacing: 36) {
                        VStack(alignment: .leading, spacing: 24) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 24).fill(.black)
                                TVVideoPreview(studio: studio).clipShape(RoundedRectangle(cornerRadius: 24))
                                if studio.direction == .receive && studio.phase != .live {
                                    VStack(spacing: 18) {
                                        Image(systemName: "tv").font(.system(size: 64)).accessibilityHidden(true)
                                        Text(studio.phase == .listening ? "Ready for a sender" : "Waiting for video").font(.title2)
                                            .multilineTextAlignment(.center).lineLimit(2)
                                        Text(
                                            studio.phase == .listening
                                                ? "Choose this Apple TV from your sender's Bonjour receivers."
                                                : "Connect to a source, or start an SRT listener."
                                        )
                                        .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 650)
                                    }.padding(40).foregroundStyle(.white)
                                }
                            }.aspectRatio(16 / 9, contentMode: .fit).frame(maxWidth: .infinity).background(.black, in: RoundedRectangle(cornerRadius: 24))
                            HStack(spacing: 24) {
                                Label(studio.phase.rawValue, systemImage: studio.phase == .live ? "dot.radiowaves.left.and.right" : "circle")
                                    .foregroundStyle(studio.phase == .live ? Color.green : Color.secondary)
                                Spacer()
                                Button("Full screen", systemImage: "arrow.up.left.and.arrow.down.right") { fullScreen = true }
                            }
                            TVSignalInspector(probe: studio.probe, network: studio.networkSummary)
                        }.frame(maxWidth: .infinity)
                        ScrollView {
                            VStack(alignment: .leading, spacing: 30) {
                                connectionControls
                                if studio.direction == .send { sourceControls }
                                if let error = studio.errorMessage {
                                    VStack(alignment: .leading, spacing: 14) {
                                        Label("Attention", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                                        Text(error).font(.callout)
                                        Button("Dismiss") { studio.dismissError() }
                                    }.padding(24).background(.quaternary, in: RoundedRectangle(cornerRadius: 18))
                                }
                                Button(studio.muted ? "Unmute audio" : "Mute audio", systemImage: studio.muted ? "speaker.wave.2" : "speaker.slash") {
                                    Task { await studio.toggleMute() }
                                }
                                Text(
                                    studio.direction == .send
                                        ? "H.264 · 1280 × 720 · 30 fps\n\(studio.transport == .webRTC ? "Opus" : "AAC") · 48 kHz · 128 kbps"
                                        : "Video and audio are decoded together. Use the signal panel to verify media delivery."
                                )
                                .font(.caption).foregroundStyle(.secondary)
                            }.padding(.horizontal, 12).padding(.bottom, 40)
                        }.frame(width: 490)
                    }
                    Spacer(minLength: 0)
                }.padding(.horizontal, 64).padding(.vertical, 40)
            }
        }
        .task {
            await studio.preparePreview()
            await studio.applyLaunchArguments()
            #if DEBUG
                let arguments = ProcessInfo.processInfo.arguments
                if let index = arguments.firstIndex(of: "--vqmetrix"), arguments.indices.contains(index + 1) {
                    await studio.selectDirection(.send)
                    qualityClient.endpoint = arguments[index + 1]
                    qualityClient.code = ProcessInfo.processInfo.environment["VQMETRIX_TEST_CODE"] ?? ""
                    showQuality = true
                    qualityClient.captureAndSend(studio: studio)
                }
            #endif

        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                qualityClient.cancel()
                Task { await studio.shutdown() }
            }
            if phase == .active { Task { await studio.preparePreview() } }
        }
        .continuityDevicePicker(isPresented: $showCameraPicker) { device in
            if let device { Task { await studio.useCamera(device) } }
        }
        .fullScreenCover(isPresented: $showQuality) { TVQualityView(client: qualityClient, studio: studio) }
        .sheet(isPresented: $showLegacy, onDismiss: { Task { await studio.preparePreview() } }) {
            NavigationStack {
                TabView {
                    PlaybackView().tabItem { Label("Playback", systemImage: "play.tv") }
                    PreferenceView().tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
                }
                .environmentObject(preference)
                .toolbar { Button("Done") { showLegacy = false } }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 28) {
            VStack(alignment: .leading, spacing: 6) {
                Label("HaishinKit", systemImage: "waveform.path").font(.largeTitle.bold())
                Text("Streaming development studio").foregroundStyle(.secondary)
            }
            Spacer()
            Button("Receive", systemImage: "arrow.down.left.video") { Task { await studio.selectDirection(.receive) } }
                .disabled(!studio.canConfigure && studio.direction != .receive)
                .tint(studio.direction == .receive ? .accentColor : .secondary)
            Button("Send", systemImage: "arrow.up.right.video") { Task { await studio.selectDirection(.send) } }
                .disabled(!studio.canConfigure && studio.direction != .send)
                .tint(studio.direction == .send ? .accentColor : .secondary)
            Button("Settings", systemImage: "ellipsis.circle") {
                Task {
                    await studio.prepareOtherProtocols()
                    showLegacy = true
                }
            }
            .disabled(!studio.canConfigure)
        }
    }

    private var connectionControls: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(studio.direction == .receive ? "Receive a stream" : "Send a stream").font(.title2.bold())
            Picker("Protocol", selection: Binding(get: { studio.transport }, set: { value in Task { await studio.selectTransport(value) } })) {
                ForEach(TVStudioModel.Transport.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.disabled(!studio.canConfigure)
            if studio.transport == .srt {
                Picker(
                    "Connection",
                    selection:
                        $studio.isListener
                ) {
                    Text("Listener").tag(true)
                    Text("Caller").tag(false)
                }.disabled(!studio.canConfigure)
                if studio.isListener {
                    TextField("Listening port", text: $studio.port).disabled(!studio.canConfigure)
                    TVAnnouncementStatus(discovery: studio.discovery)
                    Text("Start listening to announce this Apple TV on Bonjour.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    TVPeerPicker(discovery: studio.discovery, role: studio.requiredRole, enabled: studio.canConfigure) { studio.selectService($0) }
                    TextField("srt://host:port", text: $studio.endpoint)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .disabled(!studio.canConfigure)
                }
            } else {
                Text(
                    studio.transport == .rtmp
                        ? "RTMP publish / playback" : (studio.direction == .send ? "WHIP publish · Opus audio" : "WHEP playback · Opus audio")
                )
                .font(.caption).foregroundStyle(.secondary)
                TextField(studio.transport == .rtmp ? "rtmp://host/app/stream" : "https://host/stream/whip or whep", text: $studio.endpoint)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().disabled(!studio.canConfigure)
                if studio.transport == .webRTC {
                    TextField("ICE bind address (optional)", text: $studio.rtcBindAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().disabled(!studio.canConfigure)
                }
                Button("Use local test server") {
                    studio.endpoint =
                        studio.transport == .rtmp
                        ? "rtmp://127.0.0.1:1935/live/test" : "http://127.0.0.1:8889/live/test/\(studio.direction == .send ? "whip" : "whep")"
                }.disabled(!studio.canConfigure)
                Text("Run MediaMTX on your computer. Replace 127.0.0.1 with its LAN address on a physical Apple TV.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button {
                if studio.isActive { Task { await studio.stop() } } else { studio.start() }
            } label: {
                Label(
                    studio.isActive
                        ? (studio.phase == .stopping ? "Stopping…" : "Stop") : (studio.transport == .srt && studio.isListener ? "Start listening" : "Connect"),
                    systemImage: studio.isActive ? "stop.fill" : "play.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(studio.phase == .stopping || (!studio.isActive && !studio.canStart))
        }
    }

    private var sourceControls: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Source").font(.title3.bold())
            Button(studio.source == .test ? "✓ Test signal" : "Test signal", systemImage: "testtube.2") { Task { await studio.selectSource(.test) } }
                .disabled(!studio.canConfigure)
            Button(studio.source == .camera ? "✓ Continuity Camera" : "Continuity Camera", systemImage: "video") {
                Task { await studio.selectSource(.camera) }
            }.disabled(!studio.canConfigure)
            if studio.source == .camera {
                if AVContinuityDevicePickerViewController.isSupported {
                    Button(studio.cameraName == nil ? "Choose iPhone or iPad" : "Change device") { showCameraPicker = true }
                        .disabled(!studio.canConfigure)
                    Text(studio.cameraName ?? "Connect a device to enable camera and microphone capture.").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Continuity Camera requires a supported Apple TV and an iPhone or iPad. It is unavailable in Simulator.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("Moving color bars + stereo tone\nLeft 440 Hz · right 880 Hz").font(.caption).foregroundStyle(.secondary)
            }
            Button("Evaluate in VQMetrix", systemImage: "chart.xyaxis.line") { showQuality = true }
                .disabled(!studio.canStart)
            Picker("Video bitrate", selection: $studio.videoBitRate) {
                Text("1 Mbps").tag(1_000_000)
                Text("2.5 Mbps").tag(2_500_000)
                Text("5 Mbps").tag(5_000_000)
            }.disabled(!studio.canConfigure)
        }
    }
}

private struct TVVideoPreview: UIViewRepresentable {
    let studio: TVStudioModel
    func makeUIView(context: Context) -> PiPHKView {
        let view = PiPHKView(frame: .zero)
        view.videoGravity = .resizeAspect
        Task { await studio.bindPreview(view) }
        return view
    }
    func updateUIView(_ uiView: PiPHKView, context: Context) {}
}

private struct TVSignalInspector: View {
    @ObservedObject var probe: TVMediaProbe
    let network: String
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(probe.videoDescription, systemImage: "video")
                Spacer()
                Text("\(probe.videoFrames) frames").monospacedDigit()
            }
            HStack {
                Label(probe.audioDescription, systemImage: "waveform")
                Spacer()
                Text("\(probe.audioBuffers) buffers").monospacedDigit()
            }
            ProgressView(value: Double(probe.audioLevel)).accessibilityLabel("Audio signal level")
            Text(network).monospacedDigit().foregroundStyle(.secondary)
        }.font(.callout).padding(24).background(.quaternary, in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct TVAnnouncementStatus: View {
    @ObservedObject var discovery: TVBonjourDiscovery
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if discovery.isAdvertising { Label("Visible on Bonjour", systemImage: "dot.radiowaves.left.and.right").foregroundStyle(.green) }
            if let error = discovery.errorMessage { Text(error).font(.caption).foregroundStyle(.orange) }
        }
    }
}

private struct TVPeerPicker: View {
    @ObservedObject var discovery: TVBonjourDiscovery
    let role: TVBonjourDiscovery.Role
    let enabled: Bool
    let onSelect: (TVBonjourDiscovery.Service) -> Void
    private var services: [TVBonjourDiscovery.Service] { discovery.services.filter { $0.role == role } }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button(discovery.isBrowsing ? "Refresh Bonjour peers" : "Find on network", systemImage: "network") { discovery.browse() }.disabled(!enabled)
            if discovery.isBrowsing && services.isEmpty {
                Text(
                    role == .receiver
                        ? "No receivers yet. Start listening on your Mac, Apple TV, or other receiver."
                        : "No sources yet. Start a sender in listener mode on another device."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(services) { service in
                Button {
                    onSelect(service)
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(service.name)
                        Text("\(service.host):\(String(service.port))").font(.caption)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.disabled(!enabled)
            }
            if let error = discovery.errorMessage { Text(error).font(.caption).foregroundStyle(.orange) }
        }
    }
}
