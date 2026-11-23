import HaishinKit
import SwiftUI
import UniformTypeIdentifiers

struct SceneCanvasCaption: View {
    @ObservedObject var editor: SceneEditorModel
    let frameRate: String

    var body: some View {
        Text("\(editor.scene.canvasWidth ?? 1280) × \(editor.scene.canvasHeight ?? 720) · \(frameRate) fps")
    }
}

struct StudioEditingPreview: View {
    let source: PublishViewModel
    @ObservedObject var editor: SceneEditorModel

    var body: some View {
        ScreenObjectEditingPreview(
            mixer: source.mixer, gravity: .resizeAspect, selection: $editor.selectedObjectID,
            usesInspector: true, locksImageAspectRatio: editor.selectedLayer?.imageAspectRatioLocked ?? true
        ) {
            GeometryReader { geometry in
                let ratio = CGFloat(editor.scene.canvasWidth ?? 1280) / CGFloat(editor.scene.canvasHeight ?? 720)
                let width = min(geometry.size.width, geometry.size.height * ratio)
                let height = width / ratio
                ZStack {
                    Color(nsColor: .underPageBackgroundColor)
                    Color.indigo.opacity(0.18)
                    MTHKViewRepresentable(previewSource: source)
                        .frame(width: width, height: height)
                        .overlay(Rectangle().strokeBorder(Color.accentColor.opacity(0.8), lineWidth: 1))
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .allowsHitTesting(!editor.busy)
    }
}

struct SceneEditorView: View {

    @ObservedObject var model: SceneEditorModel
    @State private var importKind: StudioLayer.Kind = .image
    @State private var importing = false
    @State private var deletingScene = false
    @State private var importingScene = false
    @State private var exportingScene = false
    @State private var sceneDocument: SceneFileDocument?
    @State private var sceneName = ""

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(String(localized: "Scenes"), systemImage: "square.stack").font(.headline)
                    Spacer()
                    Menu {
                        Button(String(localized: "Open scene file…"), systemImage: "folder") { importingScene = true }
                        Button(String(localized: "Export scene file…"), systemImage: "square.and.arrow.up") {
                            Task {
                                if let document = await model.sceneDocument() {
                                    sceneDocument = document
                                    exportingScene = true
                                }
                            }
                        }
                        Divider()
                        Toggle(String(localized: "Scene visible"), isOn: Binding(get: { model.scene.rootVisible ?? true }, set: { model.setSceneVisible($0) }))
                        Button(String(localized: "New scene"), systemImage: "plus") { model.addScene() }
                        Button(String(localized: "Duplicate scene"), systemImage: "plus.square.on.square") {
                            model.addScene(duplicate: true)
                        }
                        Button(String(localized: "Delete scene"), systemImage: "trash", role: .destructive) {
                            deletingScene = true
                        }
                        .disabled(model.scenes.count == 1)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }.menuStyle(.borderlessButton).frame(width: 24).help(String(localized: "Scene actions"))
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
                Text(String(localized: "Scene name · Return to rename")).font(.caption).foregroundStyle(.secondary)
                TextField(String(localized: "Scene name"), text: $sceneName).textFieldStyle(.roundedBorder)
                    .onSubmit { model.renameScene(sceneName) }
                Text(String(localized: "Saved automatically on this Mac")).font(.caption).foregroundStyle(.secondary)
            }.frame(minWidth: 130, idealWidth: 160, maxWidth: 210)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(String(localized: "Objects"), systemImage: "square.3.layers.3d").font(.headline)
                    Spacer()
                    if model.busy { ProgressView().controlSize(.small) }
                    Menu {
                        Button(String(localized: "Capture input"), systemImage: "video") { model.addLayer(.input) }
                        Button(String(localized: "Test signal"), systemImage: "tv") { model.addLayer(.testSignal) }
                        Button(String(localized: "Text"), systemImage: "textformat") { model.addLayer(.text) }
                        Button(String(localized: "Image file…"), systemImage: "photo") {
                            importKind = .image
                            importing = true
                        }
                        Button(String(localized: "Video file…"), systemImage: "film") {
                            importKind = .video
                            importing = true
                        }
                    } label: {
                        Label(String(localized: "Add"), systemImage: "plus")
                    }.fixedSize()
                }
                ScrollView {
                    VStack(spacing: 4) {
                        if model.scene.layers.isEmpty {
                            Text(String(localized: "Add an object to compose this scene.")).font(.callout).foregroundStyle(
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
                                        if layer.kind == .unsupported { Text(String(localized: "Unsupported")).font(.caption).foregroundStyle(.secondary) }
                                        Spacer(minLength: 0)
                                    }.contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                Button {
                                    var value = layer
                                    value.visible.toggle()
                                    model.updateLayer(value)
                                } label: {
                                    Image(systemName: layer.visible && layer.kind != .unsupported ? "eye" : "eye.slash")
                                }
                                .buttonStyle(.plain).help(layer.visible ? String(localized: "Hide object") : String(localized: "Show object"))
                                .accessibilityLabel(layer.visible ? String(localized: "Hide object") : String(localized: "Show object"))
                                .disabled(layer.kind == .unsupported)
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
                    .help(String(localized: "Move forward")).accessibilityLabel(String(localized: "Move forward"))
                    Button {
                        if let id = model.selectedObjectID { model.moveLayer(id, forward: false) }
                    } label: {
                        Image(systemName: "arrow.down")
                    }
                    .help(String(localized: "Move backward")).accessibilityLabel(String(localized: "Move backward"))
                    Button {
                        if let id = model.selectedObjectID { model.duplicateLayer(id) }
                    } label: {
                        Image(systemName: "plus.square.on.square")
                    }
                    .help(String(localized: "Duplicate object")).accessibilityLabel(String(localized: "Duplicate object"))
                    Spacer()
                    Button(role: .destructive) {
                        if let id = model.selectedObjectID { model.removeLayer(id) }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help(String(localized: "Delete object")).accessibilityLabel(String(localized: "Delete object"))
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
        .fileImporter(isPresented: $importingScene, allowedContentTypes: [.haishinKitScene, .json]) { result in
            switch result {
            case .success(let url): model.openSceneFile(url)
            case .failure(let error): model.errorMessage = error.localizedDescription
            }
        }
        .fileExporter(
            isPresented: $exportingScene, document: sceneDocument, contentType: .haishinKitScene, defaultFilename: model.scene.name
        ) { result in
            if case .failure(let error) = result { model.errorMessage = error.localizedDescription }
        }
        .confirmationDialog(
            String(localized: "Delete \(model.scene.name)?"), isPresented: $deletingScene, titleVisibility: .visible
        ) {
            Button(String(localized: "Delete scene"), role: .destructive) { model.deleteScene() }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "This scene and its object layout will be removed."))
        }
        .alert(
            String(localized: "Scene editor"),
            isPresented: Binding(
                get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
        ) {
            Button(String(localized: "OK"), role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

struct SceneObjectInspector: View {
    @ObservedObject var model: SceneEditorModel
    @State private var draft: StudioLayer?
    @FocusState private var editing: Bool
    private var canvasWidth: Double { Double(model.scene.canvasWidth ?? 1280) }
    private var canvasHeight: Double { Double(model.scene.canvasHeight ?? 720) }

    var body: some View {
        StudioSection(title: String(localized: "Object inspector"), subtitle: String(localized: "Position and size in the \(Int(canvasWidth)) × \(Int(canvasHeight)) canvas")) {
            if model.selectedLayer?.kind == .unsupported {
                Text(String(localized: "This object is not supported on this platform. Its data is preserved in the scene file, and it is not rendered."))
                    .font(.callout).foregroundStyle(.secondary)
            } else if let layer = draft, model.selectedLayer != nil {
                TextField(String(localized: "Name"), text: field(\.name, fallback: layer.name)).focused($editing).onSubmit(
                    apply)
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        number("X", \.x, range: 0...canvasWidth)
                        number("Y", \.y, range: 0...canvasHeight)
                    }
                    GridRow {
                        number(String(localized: "Width"), \.width, range: min(24, canvasWidth)...canvasWidth)
                        number(String(localized: "Height"), \.height, range: min(24, canvasHeight)...canvasHeight)
                    }
                }
                if layer.kind == .image {
                    Toggle(String(localized: "Keep image aspect ratio"), isOn: Binding(
                        get: { draft?.imageAspectRatioLocked ?? true },
                        set: { draft?.imageAspectRatioLocked = $0 }))
                }
                Button(String(localized: "Apply layout")) { apply() }.disabled(model.busy)
                if layer.kind == .text {
                    Text(String(localized: "Text")).font(.callout.weight(.medium))
                    TextEditor(text: field(\.text, fallback: layer.text))
                        .frame(height: 80).border(.separator).focused($editing)
                    HStack {
                        number(String(localized: "Font size"), \.fontSize, range: 8...300)
                        ColorPicker(
                            String(localized: "Color"),
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
                    Button(String(localized: "Apply text")) { apply() }.disabled(model.busy)
                }
                Text(String(localized: "Use Return or Apply to save changes. Drag objects to move; drag the bottom-right handle to resize."))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text(String(localized: "Select an object in the list or preview.")).font(.callout).foregroundStyle(.secondary)
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
        guard [value.width, value.height, value.x, value.y, value.fontSize].allSatisfy(\.isFinite) else { return }
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
