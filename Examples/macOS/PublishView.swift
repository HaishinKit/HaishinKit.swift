import AVFoundation
import HaishinKit
import SwiftUI

enum FPS: String, CaseIterable, Identifiable {
    case fps15 = "15"
    case fps30 = "30"
    case fps60 = "60"

    var frameRate: Float64 {
        switch self {
        case .fps15:
            return 15
        case .fps30:
            return 30
        case .fps60:
            return 60
        }
    }

    var id: Self { self }
}

enum VideoEffectItem: String, CaseIterable, Identifiable, Sendable {
    case none
    case monochrome

    var id: Self { self }

    func makeVideoEffect() -> VideoEffect? {
        switch self {
        case .none:
            return nil
        case .monochrome:
            return MonochromeEffect()
        }
    }
}

struct PublishView: View {
    @EnvironmentObject private var preference: PreferenceViewModel
    @StateObject private var model = PublishViewModel()

    private var locked: Bool { model.isBusy || model.readyState != .closed }

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your broadcast, ready to go.").font(.title2.weight(.semibold))
                        Text("Compose your scene, then go live.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    SessionStatus(state: model.readyState, busy: model.isBusy, publishing: true)
                }
                ScreenObjectEditingPreview(mixer: model.mixer, gravity: .resizeAspect) {
                    MTHKViewRepresentable(previewSource: model)
                }
                .background(.black)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator.opacity(0.5)))
                HStack {
                    Label("Preview", systemImage: "viewfinder")
                    Spacer()
                    Text("1280 × 720 · \(model.currentFPS.rawValue) fps")
                        .monospacedDigit()
                }.font(.callout).foregroundStyle(.secondary)
                PublishMetricsPanel(model: model)
                Text("Select an overlay in the preview to move or resize it.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 16) {
                        StudioSection(title: "Destination", subtitle: "Where your broadcast goes") {
                            ConnectionFields().disabled(locked)
                        }
                        ScreenSourceControls(source: model.screenCapture).disabled(model.captureIsStarting)
                        if AVCaptureDevice.authorizationStatus(for: .video) != .authorized {
                            Button("Request camera access") { model.requestCameraAccess(preference) }
                                .disabled(model.captureIsStarting || locked)
                        }
                        StudioSection(title: "Video", subtitle: "Fine-tune your scene") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Frame rate").font(.callout.weight(.medium))
                                Picker("Frame rate", selection: $model.currentFPS) {
                                    ForEach(FPS.allCases) { Text("\($0.rawValue) fps").tag($0) }
                                }.pickerStyle(.segmented).labelsHidden()
                            }
                            Picker("Effect", selection: $model.visualEffectItem) {
                                Text("Original").tag(VideoEffectItem.none)
                                Text("Monochrome").tag(VideoEffectItem.monochrome)
                            }
                        }
                        StudioSection(title: "Encoder", subtitle: "Settings for the next broadcast") {
                            Picker("Resolution", selection: $model.outputResolution) {
                                ForEach(OutputResolution.allCases) { Text($0.rawValue).tag($0) }
                            }
                            Picker("Video codec", selection: $model.outputCodec) {
                                ForEach(OutputVideoCodec.allCases) { Text($0.rawValue).tag($0) }
                            }
                            Stepper("Video: \(model.videoBitRate / 1000) kbps", value: $model.videoBitRate, in: 100_000...20_000_000, step: 100_000)
                            Stepper("Audio: \(model.audioBitRate / 1000) kbps", value: $model.audioBitRate, in: 32_000...320_000, step: 16_000)
                            Toggle("Hardware encoding", isOn: $model.useHardwareEncoder)
                        }.disabled(locked)
                        VQMetrixPanel(publisher: model)
                        if let issue = model.captureIssue {
                            Label(issue, systemImage: "exclamationmark.triangle")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }.padding(20)
                }
                Divider()
                VStack(spacing: 12) {
                    Button {
                        if model.readyState == .open { model.stopPublishing() }
                        else { model.startPublishing(preference) }
                    } label: {
                        HStack {
                            if model.isBusy { ProgressView().controlSize(.small) }
                            Label(model.readyState == .open ? "Stop publishing" : "Go live",
                                  systemImage: model.readyState == .open ? "stop.fill" : "dot.radiowaves.left.and.right")
                        }.frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(model.readyState == .open ? .red : .accentColor)
                    .disabled(model.isBusy || model.readyState == .connecting || model.readyState == .closing)
                    Text("Go live sends the preview. Microphone input follows Settings → Capture.")
                        .font(.callout).foregroundStyle(.secondary)
                }.padding(20)
            }
            .frame(minWidth: 280, idealWidth: 310, maxWidth: 360)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .navigationTitle("Publish")
        .onAppear { model.startRunning(preference) }
        .onDisappear { model.stopRunning() }
        .onChange(of: model.currentFPS) { _, value in model.setFrameRate(value.frameRate) }
        .onChange(of: model.visualEffectItem) { _, value in model.setVisualEffet(value) }
        .alert("Couldn't publish", isPresented: $model.isShowError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(model.error?.localizedDescription ?? "The connection was interrupted. Check your destination and try again.")
        }
    }
}

#Preview {
    PublishView().environmentObject(PreferenceViewModel())
}
