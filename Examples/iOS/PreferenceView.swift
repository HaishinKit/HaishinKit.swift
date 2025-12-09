import HaishinKit
import SwiftUI

struct InfoRow: View {
    let title: String
    let info: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Image(systemName: "info.circle")
                .foregroundColor(.blue)
        }
        .contentShape(Rectangle())
    }
}

struct PreferenceView: View {
    @EnvironmentObject var model: PreferenceViewModel
    @State private var showingInfo = false

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("URL")
                        .frame(width: 80, alignment: .leading)
                        .foregroundColor(.secondary)
                    TextField(Preference.default.uri, text: $model.uri)
                }.padding(.vertical, 4)
                HStack {
                    Text("Name")
                        .frame(width: 80, alignment: .leading)
                        .foregroundColor(.secondary)
                    TextField(Preference.default.streamName, text: $model.streamName)
                }.padding(.vertical, 4)
            } header: {
                HStack {
                    Text("Stream")
                    Spacer()
                    Button(action: { showingInfo = true }) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 22))
                            .foregroundColor(.blue)
                    }
                }
            }
            Section {
                Picker("Format", selection: $model.audioFormat) {
                    ForEach(AudioCodecSettings.Format.allCases, id: \.self) { format in
                        Text(String(describing: format)).tag(format)
                    }
                }
            } header: {
                Text("Audio Codec Settings")
            } footer: {
                Text("AAC is widely supported. Opus offers better quality at low bitrates.")
            }
            Section {
                Toggle(isOn: $model.isHDREnabled) {
                    Text("HDR Video")
                }
                Toggle(isOn: $model.isLowLatencyRateControlEnabled) {
                    Text("Low Latency Mode")
                }
                Picker("BitRate Mode", selection: $model.bitRateMode) {
                    ForEach(model.bitRateModes, id: \.description) { index in
                        Text(index.description).tag(index)
                    }
                }
            } header: {
                Text("Video Codec Settings")
            } footer: {
                Text("HDR captures wider color range. Low latency reduces delay but may affect quality. Average bitrate is recommended for most streams.")
            }
            Section {
                Picker("Preview Type", selection: $model.viewType) {
                    ForEach(ViewType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                Picker("Audio Capture", selection: $model.audioCaptureMode) {
                    ForEach(AudioSourceServiceMode.allCases, id: \.self) { view in
                        Text(String(describing: view)).tag(view)
                    }
                }
            } header: {
                Text("Capture Settings")
            } footer: {
                Text("Metal preview is faster. AudioEngine mode is recommended for stability.")
            }
            Section {
                Button(action: {
                    model.showPublishSheet.toggle()
                }, label: {
                    Text("Memory release test for PublishView")
                }).sheet(isPresented: $model.showPublishSheet, content: {
                    PublishView()
                })
            } header: {
                Text("Debug")
            }
        }
        #if os(iOS)
        .sheet(isPresented: $showingInfo) {
            InfoGuideView(showingInfo: $showingInfo)
        }
        #endif
    }
}

#Preview {
    PreferenceView()
}
