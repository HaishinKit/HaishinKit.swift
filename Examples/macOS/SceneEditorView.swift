import HaishinKit
import SwiftUI
import UniformTypeIdentifiers

struct StudioEditingPreview: View {
    let source: PublishViewModel
    @ObservedObject var editor: SceneEditorModel

    var body: some View {
        ScreenObjectEditingPreview(
            mixer: source.mixer, gravity: .resizeAspect, selection: $editor.selectedObjectID,
            usesInspector: true
        ) {
            MTHKViewRepresentable(previewSource: source)
        }
        .allowsHitTesting(!editor.busy)
    }
}

struct SceneEditorView: View {

    @ObservedObject var model: SceneEditorModel
    @State private var importKind: StudioLayer.Kind = .image
    @State private var importing = false
    @State private var deletingScene = false
    @State private var sceneName = ""

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Scenes", systemImage: "square.stack").font(.headline)
                    Spacer()
                    Menu {
                        Button("New scene", systemImage: "plus") { model.addScene() }
                        Button("Duplicate scene", systemImage: "plus.square.on.square") {
                            model.addScene(duplicate: true)
                        }
                        Button("Delete scene", systemImage: "trash", role: .destructive) {
                            deletingScene = true
                        }
                        .disabled(model.scenes.count == 1)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }.menuStyle(.borderlessButton).frame(width: 24).help("Scene actions")
                }
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(model.scenes) { scene in
                            Button {
                                model.selectScene(scene.id)
                            } label: {
                                HStack {
                                    Image(
                                        systemName: scene.id == model.selectedSceneID
                                            ? "checkmark.circle.fill" : "circle")
                                    Text(scene.name).lineLimit(1)
                                    Spacer(minLength: 0)
                                }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        scene.id == model.selectedSceneID ? Color.accentColor.opacity(0.15) : .clear,
                                        in: RoundedRectangle(cornerRadius: 6))
                            }.buttonStyle(.plain)
                        }
                    }
                }.frame(minHeight: 80, maxHeight: 100)
                Text("Scene name · Return to rename").font(.caption).foregroundStyle(.secondary)
                TextField("Scene name", text: $sceneName).textFieldStyle(.roundedBorder)
                    .onSubmit { model.renameScene(sceneName) }
                Text("Saved automatically on this Mac").font(.caption).foregroundStyle(.secondary)
            }.frame(minWidth: 130, idealWidth: 160, maxWidth: 210)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Objects", systemImage: "square.3.layers.3d").font(.headline)
                    Spacer()
                    if model.busy { ProgressView().controlSize(.small) }
                    Menu {
                        Button("Capture input", systemImage: "video") { model.addLayer(.input) }
                        Button("Text", systemImage: "textformat") { model.addLayer(.text) }
                        Button("Image file…", systemImage: "photo") {
                            importKind = .image
                            importing = true
                        }
                        Button("Video file…", systemImage: "film") {
                            importKind = .video
                            importing = true
                        }
                    } label: {
                        Label("Add", systemImage: "plus")
                    }.fixedSize()
                }
                ScrollView {
                    VStack(spacing: 4) {
                        if model.scene.layers.isEmpty {
                            Text("Add an object to compose this scene.").font(.callout).foregroundStyle(
                                .secondary
                            ).padding(12)
                        }
                        ForEach(model.scene.layers.reversed()) { layer in
                            HStack(spacing: 8) {
                                Button {
                                    model.selectedObjectID = layer.id
                                } label: {
                                    HStack {
                                        Image(systemName: layer.kind.symbol).frame(width: 16)
                                        Text(layer.name).lineLimit(1)
                                        Spacer(minLength: 0)
                                    }.contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                Button {
                                    var value = layer
                                    value.visible.toggle()
                                    model.updateLayer(value)
                                } label: {
                                    Image(systemName: layer.visible ? "eye" : "eye.slash")
                                }
                                .buttonStyle(.plain).help(layer.visible ? "Hide object" : "Show object")
                                .accessibilityLabel(layer.visible ? "Hide object" : "Show object")
                            }.padding(8)
                                .background(
                                    layer.id == model.selectedObjectID ? Color.accentColor.opacity(0.15) : .clear,
                                    in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }.frame(minHeight: 80, maxHeight: 100)
                HStack {
                    Button {
                        if let id = model.selectedObjectID { model.moveLayer(id, forward: true) }
                    } label: {
                        Image(systemName: "arrow.up")
                    }
                    .help("Move forward").accessibilityLabel("Move forward")
                    Button {
                        if let id = model.selectedObjectID { model.moveLayer(id, forward: false) }
                    } label: {
                        Image(systemName: "arrow.down")
                    }
                    .help("Move backward").accessibilityLabel("Move backward")
                    Button {
                        if let id = model.selectedObjectID { model.duplicateLayer(id) }
                    } label: {
                        Image(systemName: "plus.square.on.square")
                    }
                    .help("Duplicate object").accessibilityLabel("Duplicate object")
                    Spacer()
                    Button(role: .destructive) {
                        if let id = model.selectedObjectID { model.removeLayer(id) }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help("Delete object").accessibilityLabel("Delete object")
                }.disabled(model.selectedLayer == nil)
            }.frame(minWidth: 170, maxWidth: .infinity)
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
        .disabled(model.busy)
        .onAppear { sceneName = model.scene.name }
        .onChange(of: model.selectedSceneID) { _, _ in sceneName = model.scene.name }
        .fileImporter(
            isPresented: $importing, allowedContentTypes: importKind == .image ? [.image] : [.movie]
        ) { result in
            switch result {
            case .success(let url): model.addLayer(importKind, file: url)
            case .failure(let error): model.errorMessage = error.localizedDescription
            }
        }
        .confirmationDialog(
            "Delete \(model.scene.name)?", isPresented: $deletingScene, titleVisibility: .visible
        ) {
            Button("Delete scene", role: .destructive) { model.deleteScene() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This scene and its object layout will be removed.")
        }
        .alert(
            "Scene editor",
            isPresented: Binding(
                get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

struct SceneObjectInspector: View {
    @ObservedObject var model: SceneEditorModel
    @State private var draft: StudioLayer?
    @FocusState private var editing: Bool

    var body: some View {
        StudioSection(title: "Object inspector", subtitle: "Position and size in the 1280 × 720 canvas") {
            if let layer = draft, model.selectedLayer != nil {
                TextField("Name", text: field(\.name, fallback: layer.name)).focused($editing).onSubmit(
                    apply)
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        number("X", \.x, range: 0...1280)
                        number("Y", \.y, range: 0...720)
                    }
                    GridRow {
                        number("Width", \.width, range: 24...1280)
                        number("Height", \.height, range: 24...720)
                    }
                }
                Button("Apply layout") { apply() }.disabled(model.busy)
                if layer.kind == .text {
                    Text("Text").font(.callout.weight(.medium))
                    TextEditor(text: field(\.text, fallback: layer.text))
                        .frame(height: 80).border(.separator).focused($editing)
                    HStack {
                        number("Font size", \.fontSize, range: 8...300)
                        ColorPicker(
                            "Color",
                            selection: Binding(
                                get: { Color(nsColor: color(draft?.color ?? "#FFFFFFFF")) },
                                set: { value in
                                    guard let rgb = NSColor(value).usingColorSpace(.sRGB) else { return }
                                    draft?.color = String(
                                        format: "#%02X%02X%02X%02X", Int((rgb.alphaComponent * 255).rounded()),
                                        Int((rgb.redComponent * 255).rounded()),
                                        Int((rgb.greenComponent * 255).rounded()),
                                        Int((rgb.blueComponent * 255).rounded()))
                                }))
                    }
                    Button("Apply text") { apply() }.disabled(model.busy)
                }
                Text("Use Return or Apply to save changes. Drag objects in the preview; scroll to resize.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Select an object in the list or preview.").font(.callout).foregroundStyle(.secondary)
            }
        }
        .onAppear { draft = model.selectedLayer }
        .onChange(of: model.selectedObjectID) { _, _ in
            editing = false
            draft = model.selectedLayer
        }
        .onChange(of: model.selectedLayer) { _, value in if !editing { draft = value } }
    }

    private func field<T>(_ key: WritableKeyPath<StudioLayer, T>, fallback: T) -> Binding<T> {
        Binding(get: { draft?[keyPath: key] ?? fallback }, set: { draft?[keyPath: key] = $0 })
    }

    private func number(
        _ title: String, _ key: WritableKeyPath<StudioLayer, Double>, range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(
                title, value: field(key, fallback: range.lowerBound),
                format: .number.precision(.fractionLength(0...1))
            )
            .textFieldStyle(.roundedBorder).focused($editing).onSubmit(apply)
        }.frame(maxWidth: .infinity)
    }

    private func apply() {
        guard var value = draft else { return }
        value.width = min(1280, max(24, value.width.isFinite ? value.width : 320))
        value.height = min(720, max(24, value.height.isFinite ? value.height : 180))
        value.x = min(1280 - value.width, max(0, value.x.isFinite ? value.x : 0))
        value.y = min(720 - value.height, max(0, value.y.isFinite ? value.y : 0))
        value.fontSize = min(300, max(8, value.fontSize.isFinite ? value.fontSize : 40))
        if value.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            value.name = value.kind.title
        }
        draft = value
        model.updateLayer(value)
        editing = false
    }

    private func color(_ hex: String) -> NSColor {
        let number = UInt32(hex.dropFirst(), radix: 16) ?? 0xFFFF_FFFF
        return NSColor(
            srgbRed: Double((number >> 16) & 255) / 255, green: Double((number >> 8) & 255) / 255,
            blue: Double(number & 255) / 255, alpha: Double((number >> 24) & 255) / 255)
    }
}
