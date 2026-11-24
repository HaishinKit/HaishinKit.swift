import HaishinKit
import SwiftUI

struct ContentView: View {
    @StateObject private var model = VisionPlaybackModel()
    @State private var showingCodecs = false
    @State private var showingConnection = false
    @State private var fillVideo = false

    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 16) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.title2).foregroundStyle(.mint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("HaishinKit").font(.title2.bold())
                    Text(visionText("Playback studio")).foregroundStyle(.secondary)
                }
                Spacer()
                Label(model.status, systemImage: model.readyState == .open ? "play.circle.fill" : "circle")
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
            }

            ZStack {
                Color.black
                PiPHKViewRepresentable(previewSource: model, videoGravity: fillVideo ? .resizeAspectFill : .resizeAspect)
                if model.readyState != .open {
                    VStack(spacing: 16) {
                        if model.busy {
                            ProgressView()
                        } else {
                            Image(systemName: model.errorMessage == nil ? "play.rectangle" : "wifi.exclamationmark")
                                .font(.system(size: 44, weight: .light)).foregroundStyle(.mint)
                        }
                        Text(visionText(model.errorMessage == nil ? "Your stream, in focus" : "Unable to play stream"))
                            .font(.title2.weight(.semibold))
                        Text(model.errorMessage ?? visionText("Set your server connection, then press Play."))
                            .foregroundStyle(.white.opacity(0.8))
                            .multilineTextAlignment(.center).frame(maxWidth: 440)
                        if model.errorMessage != nil {
                            Button(visionText("Edit connection")) { showingConnection = true }
                                .disabled(model.busy)
                        }
                    }.padding(32)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.12)))

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(visionText("Source")).font(.caption).foregroundStyle(.secondary)
                    // Never display stream keys, credentials or SRT query options in the main window.
                    Text(model.sourceLabel).font(.headline).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Button {
                    showingConnection = true
                } label: {
                    Label(visionText("Connection"), systemImage: "slider.horizontal.3")
                }.disabled(model.active || model.busy)
                Button {
                    Task { if model.active { await model.stop() } else { await model.play() } }
                } label: {
                    Label(visionText(model.active ? "Stop" : "Play"), systemImage: model.active ? "stop.fill" : "play.fill")
                        .frame(minWidth: 80)
                }
                .tint(model.active ? .red : .mint)
                .buttonStyle(.borderedProminent)
                .disabled(model.busy)
            }
            .controlSize(.large)
        }
        .padding(28)
        .background(Color(red: 0.025, green: 0.055, blue: 0.1).opacity(0.8))
        .frame(minWidth: 720, minHeight: 580)
        .ornament(attachmentAnchor: .scene(.bottom), contentAlignment: .top) {
            HStack(spacing: 20) {
                Toggle(isOn: $fillVideo) {
                    Label(visionText("Fill video"), systemImage: "arrow.up.left.and.arrow.down.right")
                }.toggleStyle(.button)
                Button(String(localized: "Device codecs", table: "CodecSupport"), systemImage: "cpu") {
                    showingCodecs = true
                }
            }.padding(16).glassBackgroundEffect()
        }
        .sheet(isPresented: $showingCodecs) { CodecSupportView() }
        .sheet(isPresented: $showingConnection) { connectionSheet }
        .onDisappear { Task { await model.stop() } }
    }

    private var connectionSheet: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text(visionText("Connection")).font(.title2.bold())
                Spacer()
                Button(visionText("Done")) { showingConnection = false }
            }
            Text(visionText("Play a stream from an RTMP, RTMPS or SRT server."))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                Text(visionText("Server URL")).font(.headline)
                TextField("rtmp://server/live", text: $model.server)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            if model.usesRTMP {
                VStack(alignment: .leading, spacing: 8) {
                    Text(visionText("Stream name / key")).font(.headline)
                    SecureField(visionText("Stream name / key"), text: $model.streamName)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
            }
            Text(visionText("For SRT, enter the complete URL including the port and any stream options. Changes apply to the next connection."))
                .font(.callout).foregroundStyle(.secondary)
            if let validation = model.validationMessage {
                Label(validation, systemImage: "exclamationmark.circle").foregroundStyle(.orange)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(32).frame(width: 600)
    }
}

func visionText(_ key: String) -> String {
    String(localized: String.LocalizationValue(key), table: "VisionStudio")
}

#Preview(windowStyle: .automatic) {
    ContentView()
}
