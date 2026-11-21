import HaishinKit
import SwiftUI

struct PlaybackView: View {
    @StateObject private var model = PlaybackViewModel()
    @EnvironmentObject private var preference: PreferenceViewModel

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("A window into your stream.").font(.title2.weight(.semibold))
                        Text("Connect to a stream and watch it here.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    SessionStatus(state: model.readyState, busy: model.isBusy, waiting: model.isWaitingForSender)
                }
                ZStack {
                    PiPHKViewRepresentable(previewSource: model)
                    if model.readyState == .closed && !model.isBusy {
                        StudioEmptyState(symbol: "play.rectangle", title: "Ready when you are",
                                         subtitle: "Enter your stream endpoint, then start playback.")
                    }
                    if model.readyState == .connecting || (model.isBusy && model.readyState != .open) {
                        VStack(spacing: 12) {
                            ProgressView().controlSize(.large)
                            Text(model.isWaitingForSender ? "Waiting for SRT sender…" : "Connecting to stream…").font(.callout)
                        }
                        .padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator.opacity(0.5)))
                HStack {
                    Label("Stream monitor", systemImage: "display")
                    Spacer()
                    Text(model.receiverSummary ?? "Playback")
                }.font(.callout).foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 16) {
                        StudioSection(title: "Source", subtitle: "Choose a stream to watch") {
                            ConnectionFields().disabled(model.isBusy || model.readyState != .closed)
                        }
                        SRTNetworkControls(discovery: model.discovery, receiving: model.readyState != .closed, busy: model.isBusy, connect: { model.start(preference, endpoint: $0) }, listen: { model.listen(port: $0) })
                    }.padding(20)
                }
                Divider()
                VStack(spacing: 12) {
                    Button {
                        if model.readyState != .closed { model.stop() }
                        else { model.start(preference) }
                    } label: {
                        HStack {
                            if model.isBusy { ProgressView().controlSize(.small) }
                            Label(model.readyState == .connecting ? "Cancel receiving" : (model.readyState == .open ? "Stop playback" : "Start playback"),
                                  systemImage: model.readyState != .closed ? "stop.fill" : "play.fill")
                        }.frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isBusy || model.readyState == .closing)
                    Text("Video and audio play through your Mac. Stop playback before changing the source.")
                        .font(.callout).foregroundStyle(.secondary)
                }.padding(20)
            }
            .frame(minWidth: 280, idealWidth: 310, maxWidth: 360)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .navigationTitle("Playback")
        .onDisappear { model.stop(); model.discovery.stop() }
        .alert("Couldn't play stream", isPresented: $model.isShowError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(model.error?.localizedDescription ?? "The connection was interrupted. Check your source and try again.")
        }
    }
}

#Preview {
    PlaybackView().environmentObject(PreferenceViewModel())
}
