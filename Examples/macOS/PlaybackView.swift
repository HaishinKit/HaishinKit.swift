import HaishinKit
import SwiftUI

struct PlaybackView: View {
    @StateObject private var model = PlaybackViewModel()
    @EnvironmentObject private var preference: PreferenceViewModel

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 16) {
                ZStack {
                    PiPHKViewRepresentable(previewSource: model)
                    if model.readyState == .closed && !model.isBusy {
                        StudioEmptyState(symbol: "play.rectangle", title: String(localized: "Ready when you are"),
                                         subtitle: String(localized: "Enter your stream endpoint, then start playback."))
                    }
                    if model.readyState == .connecting || (model.isBusy && model.readyState != .open) {
                        VStack(spacing: 12) {
                            ProgressView().controlSize(.large)
                            Text(model.isWaitingForSender ? String(localized: "Waiting for SRT sender…") : String(localized: "Connecting to stream…")).font(.callout)
                        }
                        .padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator.opacity(0.5)))
                HStack {
                    Label(String(localized: "Stream monitor"), systemImage: "display")
                    Spacer()
                    Text(model.receiverSummary ?? String(localized: "Playback"))
                }.font(.callout).foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 16) {
                        StudioSection(title: String(localized: "Source"), subtitle: String(localized: "Choose a stream to watch")) {
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
                            Label(model.readyState == .connecting ? String(localized: "Cancel receiving") : (model.readyState == .open ? String(localized: "Stop playback") : String(localized: "Start playback")),
                                  systemImage: model.readyState != .closed ? "stop.fill" : "play.fill")
                        }.frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isBusy || model.readyState == .closing)
                    Text(String(localized: "Video and audio play through your Mac. Stop playback before changing the source."))
                        .font(.callout).foregroundStyle(.secondary)
                }.padding(20)
            }
            .frame(minWidth: 280, idealWidth: 310, maxWidth: 360)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .navigationTitle(String(localized: "Playback") + " · " + SessionStatus(state: model.readyState, busy: model.isBusy, waiting: model.isWaitingForSender).title)
        .onDisappear { model.stop(); model.discovery.stop() }
        .alert(String(localized: "Couldn't play stream"), isPresented: $model.isShowError) {
            Button(String(localized: "OK"), role: .cancel) { }
        } message: {
            Text(model.error?.localizedDescription ?? String(localized: "The connection was interrupted. Check your source and try again."))
        }
    }
}

#Preview {
    PlaybackView().environmentObject(PreferenceViewModel())
}
