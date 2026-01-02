import HaishinKit
import SwiftUI

struct PreferenceView: View {
    @EnvironmentObject var model: PreferenceViewModel

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
                Text("Stream")
            }
            Section {
                Picker("Format", selection: $model.audioFormat) {
                    ForEach(AudioCodecSettings.Format.allCases, id: \.self) { format in
                        Text(String(describing: format)).tag(format)
                    }
                }
            } header: {
                Text("Audio Codec Settings")
            }
            Section {
                Toggle(isOn: $model.isLowLatencyRateControlEnabled) {
                    Text("LowLatency")
                }
                Picker("BitRateMode", selection: $model.bitRateMode) {
                    ForEach(model.bitRateModes, id: \.description) { index in
                        Text(index.description).tag(index)
                    }
                }
            } header: {
                Text("Video Codec Settings")
            }
            Section {
                Picker("View Type", selection: $model.viewType) {
                    ForEach(ViewType.allCases, id: \.self) { view in
                        Text(String(describing: view)).tag(view)
                    }
                }
                Picker("Audio Capture Mode", selection: $model.audioCaptureMode) {
                    ForEach(AudioSourceServiceMode.allCases, id: \.self) { view in
                        Text(String(describing: view)).tag(view)
                    }
                }
                Toggle(isOn: $model.isGPURendererEnabled) {
                    Text("Use GPU rendering.")
                }
            } header: {
                Text("Others")
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
                Text("Test Case")
            }
        }
    }
}

#Preview {
    PreferenceView()
}
