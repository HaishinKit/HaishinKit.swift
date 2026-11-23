import SwiftUI

struct MixerSettingsView: View {
    @ObservedObject var model: PublishViewModel
    @ObservedObject var editor: SceneEditorModel
    @State private var width = 1280
    @State private var height = 720

    var body: some View {
        StudioSection(title: "MediaMixer", subtitle: String(localized: "Composition size and output timing")) {
            Menu(String(localized: "Canvas presets")) {
                ForEach(OutputResolution.allCases) { resolution in
                    Button(resolution.rawValue) {
                        editor.setCanvasSize(width: Int(resolution.size.width), height: Int(resolution.size.height))
                    }
                }
                Button(String(localized: "1080 × 1920 (portrait)")) { editor.setCanvasSize(width: 1080, height: 1920) }
                Button("3840 × 2160") { editor.setCanvasSize(width: 3840, height: 2160) }
            }
            HStack {
                VStack(alignment: .leading) {
                    Text(String(localized: "Width")).font(.caption)
                    TextField(String(localized: "Width"), value: $width, format: .number.grouping(.never))
                }
                Text("×").foregroundStyle(.secondary)
                VStack(alignment: .leading) {
                    Text(String(localized: "Height")).font(.caption)
                    TextField(String(localized: "Height"), value: $height, format: .number.grouping(.never))
                }
            }.textFieldStyle(.roundedBorder)
            Button(String(localized: "Apply canvas size")) { editor.setCanvasSize(width: width, height: height) }
                .disabled(editor.busy || !(1...8192).contains(width) || !(1...8192).contains(height))
            Text(String(localized: "Saved with the scene. Overlay positions stay unchanged. Encoder resolution is configured separately."))
                .font(.caption).foregroundStyle(.secondary)
            Picker(String(localized: "Mixer FPS"), selection: $model.mixerFPS) {
                ForEach(FPS.allCases) { Text("\($0.rawValue) fps").tag($0) }
            }.pickerStyle(.segmented)
        }
        .disabled(editor.busy)
        .onAppear(perform: synchronize)
        .onChange(of: editor.scene.id) { _, _ in synchronize() }
        .onChange(of: editor.scene.canvasWidth) { _, _ in synchronize() }
        .onChange(of: editor.scene.canvasHeight) { _, _ in synchronize() }
    }

    private func synchronize() {
        width = editor.scene.canvasWidth ?? 1280
        height = editor.scene.canvasHeight ?? 720
    }
}
