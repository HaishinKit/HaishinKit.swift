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
    @Binding var sceneOpenRequest: SceneOpenRequest?

    init(sceneOpenRequest: Binding<SceneOpenRequest?> = .constant(nil)) {
        _sceneOpenRequest = sceneOpenRequest
    }
    @EnvironmentObject private var preference: PreferenceViewModel
    @StateObject private var model = PublishViewModel()

    private var locked: Bool { model.isBusy || model.isChangingDynamicRange || model.readyState != .closed }

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 16) {
                StudioEditingPreview(source: model, editor: model.sceneEditor)
                .frame(minHeight: 160)
                .background(.black)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator.opacity(0.5)))
                HStack {
                    Label(String(localized: "Preview"), systemImage: "viewfinder")
                    Spacer()
                    SceneCanvasCaption(editor: model.sceneEditor, frameRate: model.mixerFPS.rawValue)
                        .monospacedDigit()
                }.font(.callout).foregroundStyle(.secondary)
                Text(String(localized: "Tinted area is outside the video canvas.")).font(.caption).foregroundStyle(.secondary)
                PublishMetricsPanel(model: model)
                SceneEditorView(model: model.sceneEditor)
            }
            .padding(24)
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 16) {
                        StudioSection(title: String(localized: "Destination"), subtitle: String(localized: "Where your broadcast goes")) {
                            ConnectionFields().disabled(locked)
                        }
                        SceneObjectInspector(model: model.sceneEditor)
                        ScreenSourceControls(source: model.screenCapture).disabled(model.captureIsStarting)
                        if AVCaptureDevice.authorizationStatus(for: .video) != .authorized {
                            Button(String(localized: "Request camera access")) { model.requestCameraAccess(preference) }
                                .disabled(model.captureIsStarting || locked)
                        }
                        MixerSettingsView(model: model, editor: model.sceneEditor).disabled(model.isBusy || model.isChangingDynamicRange || model.captureIsStarting)
                        StudioSection(title: String(localized: "Capture"), subtitle: String(localized: "Input frame rate and effects")) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(String(localized: "Frame rate")).font(.callout.weight(.medium))
                                Picker(String(localized: "Frame rate"), selection: $model.currentFPS) {
                                    ForEach(FPS.allCases) { Text("\($0.rawValue) fps").tag($0) }
                                }.pickerStyle(.segmented).labelsHidden()
                            }
                            Picker(String(localized: "Effect"), selection: $model.visualEffectItem) {
                                Text(String(localized: "Original")).tag(VideoEffectItem.none)
                                Text(String(localized: "Monochrome")).tag(VideoEffectItem.monochrome)
                            }
                        }
                        StudioSection(title: String(localized: "Encoder"), subtitle: String(localized: "Settings for the next broadcast")) {
                            Picker(String(localized: "Resolution"), selection: $model.outputResolution) {
                                ForEach(OutputResolution.allCases) { Text($0.rawValue).tag($0) }
                            }
                            Picker(String(localized: "Video codec"), selection: $model.outputCodec) {
                                ForEach(OutputVideoCodec.allCases) { Text($0.rawValue).tag($0) }
                            }
                            if model.outputCodec == .hevcMain10 {
                                Text(String(localized: "10-bit HLG over Enhanced RTMP requires a compatible server and player."))
                                    .font(.callout).foregroundStyle(.secondary)
                            }
                            Stepper(String(localized: "Video: \(model.videoBitRate / 1000) kbps"), value: $model.videoBitRate, in: 100_000...20_000_000, step: 100_000)
                            Stepper(String(localized: "Audio: \(model.audioBitRate / 1000) kbps"), value: $model.audioBitRate, in: 32_000...320_000, step: 16_000)
                            Toggle(String(localized: "Hardware encoding"), isOn: $model.useHardwareEncoder)
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
                    if let issue = model.encodingConfigurationIssue {
                        Label(issue, systemImage: "exclamationmark.triangle")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Button {
                        if model.readyState == .open { model.stopPublishing() }
                        else { model.startPublishing(preference) }
                    } label: {
                        HStack {
                            if model.isBusy { ProgressView().controlSize(.small) }
                            Label(model.readyState == .open ? String(localized: "Stop publishing") : String(localized: "Go live"),
                                  systemImage: model.readyState == .open ? "stop.fill" : "dot.radiowaves.left.and.right")
                        }.frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(model.readyState == .open ? .red : .accentColor)
                    .disabled(model.isBusy || model.readyState == .connecting || model.readyState == .closing)
                    Text(String(localized: "Go live sends the preview. Microphone input follows Settings → Capture."))
                        .font(.callout).foregroundStyle(.secondary)
                }.padding(20)
            }
            .frame(minWidth: 280, idealWidth: 310, maxWidth: 360)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .navigationTitle(String(localized: "Publish") + " · " + SessionStatus(state: model.readyState, busy: model.isBusy, publishing: true).title)
        .onAppear { model.startRunning(preference) }
        .onDisappear { model.stopRunning() }
        .task(id: sceneOpenRequest?.id) {
            if let request = sceneOpenRequest {
                await model.openSceneFileWhenReady(request.url)
                if !Task.isCancelled, sceneOpenRequest?.id == request.id { sceneOpenRequest = nil }
            }
        }
        .onChange(of: model.mixerFPS) { _, value in model.setMixerFrameRate(value.frameRate) }
        .onChange(of: model.currentFPS) { _, value in model.setFrameRate(value.frameRate) }
        .onChange(of: model.visualEffectItem) { _, value in model.setVisualEffet(value) }
        .alert(String(localized: "Couldn't publish"), isPresented: $model.isShowError) {
            Button(String(localized: "OK"), role: .cancel) { }
        } message: {
            Text(model.error?.localizedDescription ?? String(localized: "The connection was interrupted. Check your destination and try again."))
        }
    }
}

#Preview {
    PublishView().environmentObject(PreferenceViewModel())
}
