import AVFoundation
import CoreImage
import HaishinKit
import SwiftUI

struct StudioLayer: Codable, Identifiable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case input, text, image, video, group, unsupported
        var title: String {
            switch self {
            case .input: "Capture input"
            case .text: "Text"
            case .image: "Image"
            case .video: "Video"
            case .group: "Group"
            case .unsupported: "Unsupported object"
            }
        }
        var symbol: String {
            switch self {
            case .input: "video"
            case .text: "textformat"
            case .image: "photo"
            case .video: "film"
            case .group: "square.stack.3d.up"
            case .unsupported: "eye.slash"
            }
        }
    }
    var id = "example-overlay-" + UUID().uuidString
    var kind: Kind
    var name: String
    var x: Double = 24
    var y: Double = 24
    var width: Double = 320
    var height: Double = 180
    var visible = true
    var text = "New text"
    var fontSize: Double = 40
    var color = "#FFFFFFFF"
    var media: String?
    var snapshotData: Data?
    var absoluteLayout: Bool?
}

struct StudioScene: Codable, Identifiable, Equatable, Sendable {
    var id = UUID().uuidString
    var name: String
    var layers: [StudioLayer]
    var canvasWidth: Int?
    var canvasHeight: Int?
    var snapshotData: Data?
    var rootVisible: Bool?
    static func initial() -> Self {
        Self(
            name: "Scene 1",
            layers: [
                StudioLayer(kind: .input, name: "Capture input", x: 0, y: 0, width: 1280, height: 720)
            ])
    }
}

@ScreenActor
private final class StudioSceneRenderer {
    nonisolated init(mixer: MediaMixer) { self.mixer = mixer }
    private let mixer: MediaMixer
    private var objects: [String: ScreenObject] = [:]
    private var effect: VideoEffectItem = .none
    private var effects: [String: VideoEffect] = [:]
    private var sceneVisible = true
    private var installedSceneID: String?

    func install(_ scene: StudioScene, mediaDirectory: URL) async throws {
        try SceneFileDocument.validate(SceneSnapshotCodec.snapshot(scene), resources: [:], allowMissingResources: true)
        let screen = mixer.screen
        let assets = SceneFileRepository.mediaURL(id: scene.id, root: mediaDirectory)
        let targetVisible = scene.rootVisible ?? true
        var replacement: [String: ScreenObject] = [:]
        var replacementEffects: [String: VideoEffect] = [:]
        do {
            for layer in scene.layers {
                let raw = try SceneSnapshotCodec.node(layer)
                let resolved = try SceneSnapshotCodec.map(raw) { node in
                    var elements = node.elements
                    if ["image", "asset"].contains(node.type), let source = elements["source"], source.hasPrefix("media/") {
                        let filename = try SceneFileDocument.mediaName(source)
                        elements["source"] = assets.appendingPathComponent(filename).absoluteString
                    }
                    return elements
                }
                if installedSceneID == scene.id, let existing = objects[layer.id] {
                    replacement[layer.id] = existing
                    for node in Self.nodes(resolved) { replacementEffects[node.id] = effects[node.id] }
                    continue
                }
                guard let object = ScreenObjectFactory().make(resolved) else {
                    throw SceneFileError(message: "Unsupported screen object: \(raw.type)")
                }
                func validate(_ node: ScreenObjectSnapshot) throws {
                    guard ["screen", "container", "video", "text", "image", "asset"].contains(node.type) else { return }
                    if node.type == "image", (object.findById(node.id) as? ImageScreenObject)?.ciImage == nil {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    if node.type == "asset", (object.findById(node.id) as? AssetScreenObject)?.isReading != true {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    for child in node.children { try validate(child) }
                }
                do { try validate(resolved) } catch {
                    Self.stopAssets(object, snapshot: resolved)
                    throw error
                }
                for node in Self.nodes(resolved) where node.type == "video" {
                    if let video = object.findById(node.id) as? VideoScreenObject, let effect = effect.makeVideoEffect() {
                        _ = video.registerVideoEffect(effect)
                        replacementEffects[node.id] = effect
                    }
                }
                replacement[layer.id] = object
                apply(layer, to: object)
                object.isVisible = targetVisible && layer.visible && layer.kind != .unsupported
            }
        } catch {
            for (id, object) in replacement where objects[id] !== object {
                Self.stopAssets(object, snapshot: ScreenObjectSnapshotFactory().make(object))
            }
            throw error
        }
        // Replace the scene in one rendering-actor turn, after every source is ready.
        for (id, object) in objects {
            if replacement[id] !== object { Self.stopAssets(object, snapshot: ScreenObjectSnapshotFactory().make(object)) }
            screen.removeChild(object)
        }
        let snapshot = ScreenObjectSnapshotFactory().make(screen)
        for child in snapshot.children where !child.id.hasPrefix("example-overlay-") {
            screen.findById(child.id)?.isVisible = false
        }
        screen.size = CGSize(width: scene.canvasWidth ?? 1280, height: scene.canvasHeight ?? 720)
        screen.backgroundColor = NSColor.black.cgColor
        objects = replacement
        effects = replacementEffects
        sceneVisible = targetVisible
        installedSceneID = scene.id
        for layer in scene.layers {
            if let object = objects[layer.id] { apply(layer, to: object) }
            try screen.addChild(objects[layer.id])
        }
    }

    func update(_ layer: StudioLayer) async {
        guard let object = objects[layer.id] else { return }
        apply(layer, to: object)
    }

    private func apply(_ layer: StudioLayer, to object: ScreenObject) {
        object.isVisible = sceneVisible && layer.visible && layer.kind != .unsupported
        object.size = CGSize(width: layer.width, height: layer.height)
        if let node = try? SceneSnapshotCodec.node(layer) {
            object.horizontalAlignment = .init(rawValue: node.horizontalAlignment) ?? .left
            object.verticalAlignment = .init(rawValue: node.verticalAlignment) ?? .top
            object.layoutMargin = .init(
                top: CGFloat(node.layoutMargin.top), left: CGFloat(node.layoutMargin.left), bottom: CGFloat(node.layoutMargin.bottom),
                right: CGFloat(node.layoutMargin.right))
        }
        if let text = object as? TextScreenObject {
            text.elements = [
                "value": layer.text, "fontSize": String(layer.fontSize), "color": layer.color,
            ]
        }
        object.invalidateLayout()
    }

    func read(_ layers: [StudioLayer]) -> [StudioLayer] {
        layers.compactMap { layer in
            guard let object = objects[layer.id] else { return layer }
            guard object.parent != nil else { return nil }
            var updated = layer
            updated.visible = !sceneVisible || layer.kind == .unsupported ? layer.visible : object.isVisible
            updated.width = object.size.width
            updated.height = object.size.height
            updated.x = object.bounds.isEmpty ? object.layoutMargin.left : object.bounds.minX
            updated.y = object.bounds.isEmpty ? object.layoutMargin.top : object.bounds.minY
            let raw = ScreenObjectSnapshotFactory().make(object)
            let basis = layer.snapshotData.flatMap { try? JSONDecoder().decode(ScreenObjectSnapshot.self, from: $0) }
            let retained = Dictionary(uniqueKeysWithValues: basis.map { Self.nodes($0) }.map { $0.map { ($0.id, $0.elements) } } ?? [])
            let snapshot = SceneSnapshotCodec.map(
                raw,
                transform: { node in
                    var elements = (retained[node.id] ?? [:]).merging(node.elements) { _, updated in updated }
                    if ["image", "asset"].contains(node.type), let source = elements["source"], let url = URL(string: source), url.isFileURL
                    {
                        elements["source"] = "media/" + url.lastPathComponent
                    }
                    return elements
                })
            updated.snapshotData = try? SceneSnapshotCodec.encode(snapshot)
            updated.absoluteLayout = false
            if let text = object as? TextScreenObject {
                updated.text = text.string
                updated.fontSize = Double(text.elements["fontSize"] ?? "40") ?? 40
                updated.color = text.elements["color"] ?? "#FFFFFFFF"
            }
            return updated
        }
    }

    private static func nodes(_ node: ScreenObjectSnapshot) -> [ScreenObjectSnapshot] {
        [node] + node.children.flatMap { nodes($0) }
    }

    private static func stopAssets(_ object: ScreenObject, snapshot: ScreenObjectSnapshot) {
        for node in nodes(snapshot) { (object.findById(node.id) as? AssetScreenObject)?.cancelReading() }
    }

    func suspend() {
        installedSceneID = nil
        objects.values.forEach { Self.stopAssets($0, snapshot: ScreenObjectSnapshotFactory().make($0)) }
    }

    func setEffect(_ value: VideoEffectItem) {
        effect = value
        let all = objects.values.flatMap { object in
            Self.nodes(ScreenObjectSnapshotFactory().make(object)).compactMap { object.findById($0.id) as? VideoScreenObject }
        }
        for video in all {
            let id = video.id
            if let previous = effects.removeValue(forKey: id) {
                _ = video.unregisterVideoEffect(previous)
            }
            if let next = value.makeVideoEffect() {
                _ = video.registerVideoEffect(next)
                effects[id] = next
            }
        }
    }
}

@MainActor
final class SceneEditorModel: ObservableObject {
    @Published private(set) var scenes: [StudioScene]
    @Published private(set) var selectedSceneID: String
    @Published var selectedObjectID: String?
    @Published private(set) var busy = false
    @Published var errorMessage: String?
    private let renderer: StudioSceneRenderer
    private var refreshTask: Task<Void, Never>?
    private var operation: Task<Void, Never>?
    private var started = false
    private var loadedFiles = false
    private let saveSession = SceneSaveSession()
    private var saveTask: Task<Void, Error>?
    let sceneDirectory: URL
    private let defaults: UserDefaults
    private static let storageKey = "macos.studio.scenes.v1"
    let mediaDirectory: URL

    var scene: StudioScene { scenes.first { $0.id == selectedSceneID } ?? scenes[0] }
    var selectedLayer: StudioLayer? { scene.layers.first { $0.id == selectedObjectID } }

    init(mixer: MediaMixer, defaults: UserDefaults = .standard, sceneDirectory: URL? = nil, mediaDirectory: URL? = nil) {
        self.defaults = defaults
        self.sceneDirectory =
            sceneDirectory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(
                "HaishinKit/Scenes", isDirectory: true)
        renderer = StudioSceneRenderer(mixer: mixer)
        self.mediaDirectory =
            mediaDirectory
            ?? FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HaishinKit/SceneWorkspaceMedia", isDirectory: true)
        let saved = defaults.data(forKey: Self.storageKey).flatMap {
            try? JSONDecoder().decode([StudioScene].self, from: $0)
        }
        let scenes = saved.flatMap { $0.isEmpty ? nil : $0 } ?? [.initial()]
        self.scenes = scenes
        selectedSceneID = defaults.string(forKey: Self.storageKey + ".selection") ?? scenes[0].id
    }

    func start() async {
        guard !started else { return }
        started = true
        busy = true
        if !loadedFiles {
            let legacy = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(
                "HaishinKit/SceneMedia")
            for scene in scenes {
                let target = SceneFileRepository.mediaURL(id: scene.id, root: mediaDirectory)
                for filename in scene.layers.compactMap(\.media) where SceneFileDocument.safeFilename(filename) {
                    let file = target.appendingPathComponent(filename)
                    if !FileManager.default.fileExists(atPath: file.path),
                        FileManager.default.fileExists(atPath: legacy.appendingPathComponent(filename).path)
                    {
                        try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
                        try? FileManager.default.copyItem(at: legacy.appendingPathComponent(filename), to: file)
                    }
                }
            }
        }
        if !loadedFiles {
            await loadSavedFiles()
            loadedFiles = true
        }
        do { try await renderer.install(scene, mediaDirectory: mediaDirectory) } catch {
            errorMessage = "Could not restore this scene: \(error.localizedDescription)"
        }
        await save()
        busy = false
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if !self.busy { await self.synchronize() }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    func synchronize() async {
        let id = selectedSceneID
        let current = scene.layers
        let updated = await renderer.read(current)
        guard !busy, selectedSceneID == id, current == scene.layers else { return }
        if current != updated {
            scenes[sceneIndex].layers = updated
            if !updated.contains(where: { $0.id == selectedObjectID }) { selectedObjectID = nil }
            await save()
        }
    }

    func stop() async {
        refreshTask?.cancel()
        refreshTask = nil
        await operation?.value
        await synchronize()
        await renderer.suspend()
        started = false
    }

    private var sceneIndex: Int { scenes.firstIndex { $0.id == selectedSceneID } ?? 0 }
    private func save() async {
        defaults.set(selectedSceneID, forKey: Self.storageKey + ".selection")
        let previous = saveTask
        let scenes = scenes
        let directory = sceneDirectory
        let session = saveSession
        let next = Task.detached {
            _ = try? await previous?.value
            try session.save(scenes, directory: directory)
        }
        saveTask = next
        do { try await next.value } catch { errorMessage = error.localizedDescription }
    }

    private func loadSavedFiles() async {
        let session = saveSession
        let directory = sceneDirectory
        let media = mediaDirectory
        do {
            let result = try await Task.detached { () -> ([StudioScene], [String], Bool) in
                guard FileManager.default.fileExists(atPath: directory.path) else { return ([], [], false) }
                let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                    .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
                var restored: [StudioScene] = []
                var failures: [String] = []
                for file in files {
                    do {
                        let scene = try session.read(file, mediaDirectory: media)
                        guard !restored.contains(where: { $0.id == scene.id }) else {
                            throw SceneFileError(message: "Duplicate scene identifier.")
                        }
                        restored.append(scene)
                    } catch { failures.append(file.lastPathComponent + ": " + error.localizedDescription) }
                }
                return (restored, failures, !files.isEmpty)
            }.value
            if result.2 {
                // Preserve unreadable packages; a fresh scene must not overwrite them.
                scenes = result.0.isEmpty ? [.initial()] : result.0
                if !scenes.contains(where: { $0.id == selectedSceneID }) { selectedSceneID = scenes[0].id }
            }
            if !scenes.contains(where: { $0.id == selectedSceneID }) { selectedSceneID = scenes[0].id }
            if !result.1.isEmpty {
                errorMessage = "Some scene files could not be opened. They were preserved.\n" + result.1.joined(separator: "\n")
            }
        } catch {
            scenes = [.initial()]
            selectedSceneID = scenes[0].id
            errorMessage = "Could not read saved scenes: \(error.localizedDescription)"
        }
    }

    func waitForOperation() async { await operation?.value }

    private func perform(_ action: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true
        operation = Task {
            defer { busy = false }
            do {
                _ = try? await saveTask?.value
                try await action()
                await save()
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func selectScene(_ id: String) {
        guard id != selectedSceneID, let target = scenes.first(where: { $0.id == id }) else { return }
        perform {
            self.scenes[self.sceneIndex].layers = await self.renderer.read(self.scene.layers)
            try await self.renderer.install(target, mediaDirectory: self.mediaDirectory)
            self.selectedSceneID = id
            self.selectedObjectID = nil
        }
    }

    func addScene(duplicate: Bool = false) {
        perform {
            self.scenes[self.sceneIndex].layers = await self.renderer.read(self.scene.layers)
            var scene = duplicate ? self.scene : StudioScene(name: "New scene", layers: [])
            scene.id = UUID().uuidString
            scene.name = duplicate ? scene.name + " copy" : "Scene \(self.scenes.count + 1)"
            var committed = false
            let createdID = scene.id
            defer { if !committed { try? FileManager.default.removeItem(at: SceneFileRepository.mediaURL(id: createdID, root: self.mediaDirectory)) } }
            if duplicate { try SceneFileRepository.copyMedia(from: self.scene.id, to: scene.id, root: self.mediaDirectory) }
            scene.layers = try scene.layers.map { try SceneSnapshotCodec.duplicate($0) }
            try await self.renderer.install(scene, mediaDirectory: self.mediaDirectory)
            self.scenes.append(scene)
            committed = true
            self.selectedSceneID = scene.id
            self.selectedObjectID = nil
        }
    }

    func renameScene(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy, !trimmed.isEmpty else { return }
        perform { self.scenes[self.sceneIndex].name = trimmed }
    }

    func setSceneVisible(_ visible: Bool) {
        perform {
            var updated = self.scene
            updated.layers = await self.renderer.read(updated.layers)
            updated.rootVisible = visible
            try await self.renderer.install(updated, mediaDirectory: self.mediaDirectory)
            self.scenes[self.sceneIndex] = updated
        }
    }

    func deleteScene() {
        guard scenes.count > 1 else { return }
        perform {
            let oldID = self.selectedSceneID
            let next = self.scenes.first { $0.id != oldID }!
            try await self.renderer.install(next, mediaDirectory: self.mediaDirectory)
            _ = try? await self.saveTask?.value
            try self.saveSession.delete(id: oldID, directory: self.sceneDirectory, mediaDirectory: self.mediaDirectory)
            self.scenes.removeAll { $0.id == oldID }
            self.selectedSceneID = next.id
            self.selectedObjectID = nil
        }
    }

    func addLayer(_ kind: StudioLayer.Kind, file: URL? = nil) {
        perform {
            var layer = StudioLayer(kind: kind, name: kind.title)
            var importedFile: URL?
            var committed = false
            defer { if !committed, let importedFile { try? FileManager.default.removeItem(at: importedFile) } }
            switch kind {
            case .input:
                layer.width = 640
                layer.height = 360
            case .text:
                layer.width = 520
                layer.height = 100
            case .group, .unsupported: return
            case .image, .video:
                guard let file else { return }
                let sceneMedia = SceneFileRepository.mediaURL(id: self.scene.id, root: self.mediaDirectory)
                let access = file.startAccessingSecurityScopedResource()
                defer { if access { file.stopAccessingSecurityScopedResource() } }
                try FileManager.default.createDirectory(
                    at: sceneMedia, withIntermediateDirectories: true)
                let filename = UUID().uuidString + "." + file.pathExtension
                let destination = sceneMedia.appendingPathComponent(filename)
                let existingBytes = try SceneFileRepository.document(self.scene, mediaDirectory: self.mediaDirectory)
                    .resources.values.reduce(0) { $0 + $1.count }
                try await Task.detached(priority: .userInitiated) {
                    let data = try Data(contentsOf: file, options: .mappedIfSafe)
                    guard data.count <= SceneFile.maximumResourceBytes - existingBytes else {
                        throw SceneFileError(message: "Scene media exceeds 128 MB.")
                    }
                    try data.write(to: destination, options: .atomic)
                }.value
                importedFile = destination
                layer.media = filename
                layer.name = file.deletingPathExtension().lastPathComponent
                let sourceSize: CGSize
                if kind == .image {
                    guard
                        let image = CIImage(contentsOf: sceneMedia.appendingPathComponent(filename))
                    else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    sourceSize = image.extent.size
                } else {
                    let asset = AVURLAsset(url: sceneMedia.appendingPathComponent(filename))
                    guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    let size = try await track.load(.naturalSize)
                    let transform = try await track.load(.preferredTransform)
                    sourceSize = CGRect(origin: .zero, size: size).applying(transform).size
                }
                guard sourceSize.width.isFinite, sourceSize.height.isFinite, sourceSize.width > 0,
                    sourceSize.height > 0
                else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                let scale = min(480 / sourceSize.width, 270 / sourceSize.height)
                layer.width = sourceSize.width * scale
                layer.height = sourceSize.height * scale
            }
            var updated = self.scene
            updated.layers = await self.renderer.read(updated.layers)
            updated.layers.append(layer)
            try await self.renderer.install(updated, mediaDirectory: self.mediaDirectory)
            self.scenes[self.sceneIndex] = updated
            self.selectedObjectID = layer.id
            committed = true
        }
    }

    func updateLayer(_ layer: StudioLayer) {
        var layer = layer
        if let previous = scene.layers.first(where: { $0.id == layer.id }),
            previous.x != layer.x || previous.y != layer.y || previous.width != layer.width || previous.height != layer.height {
            layer.absoluteLayout = true
        }
        guard !busy, let index = scene.layers.firstIndex(where: { $0.id == layer.id }) else { return }
        perform {
            var candidate = self.scene
            candidate.layers[index] = layer
            try SceneFileDocument.validate(SceneSnapshotCodec.snapshot(candidate), resources: [:], allowMissingResources: true)
            await self.renderer.update(layer)
            self.scenes[self.sceneIndex].layers[index] = layer
        }
    }

    func removeLayer(_ id: String) {
        changeLayers { $0.removeAll { $0.id == id } }
    }

    func duplicateLayer(_ id: String) {
        changeLayers { layers in
            guard let original = layers.first(where: { $0.id == id }) else { return }
            guard var copy = try? SceneSnapshotCodec.duplicate(original) else { return }
            copy.absoluteLayout = true
            copy.name += " copy"
            copy.x = min(max(0, 1280 - copy.width), copy.x + 24)
            copy.y = min(max(0, 720 - copy.height), copy.y + 24)
            layers.append(copy)
        }
    }

    func moveLayer(_ id: String, forward: Bool) {
        changeLayers { layers in
            guard let index = layers.firstIndex(where: { $0.id == id }) else { return }
            let next = index + (forward ? 1 : -1)
            guard layers.indices.contains(next) else { return }
            layers.swapAt(index, next)
        }
    }

    private func changeLayers(_ action: @escaping (inout [StudioLayer]) -> Void) {
        perform {
            var updated = self.scene
            updated.layers = await self.renderer.read(updated.layers)
            action(&updated.layers)
            try await self.renderer.install(updated, mediaDirectory: self.mediaDirectory)
            self.scenes[self.sceneIndex] = updated
            if !updated.layers.contains(where: { $0.id == self.selectedObjectID }) {
                self.selectedObjectID = nil
            }
        }
    }

    func sceneDocument() async -> SceneFileDocument? {
        guard !busy else { return nil }
        await synchronize()
        guard !busy else { return nil }
        busy = true
        defer { busy = false }
        let selected = scene
        let media = mediaDirectory
        do { return try await Task.detached { try SceneFileRepository.document(selected, mediaDirectory: media) }.value } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func openSceneFile(_ url: URL) {
        perform {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let media = self.mediaDirectory
            let document = try await Task.detached { try SceneFileDocument.read(url) }.value
            let candidate = document.snapshot.id
            let id =
                self.scenes.contains(where: { $0.id == candidate })
                    || FileManager.default.fileExists(atPath: SceneFileRepository.mediaURL(id: candidate, root: media).path)
                ? UUID().uuidString : candidate
            var committed = false
            defer { if !committed { try? FileManager.default.removeItem(at: SceneFileRepository.mediaURL(id: id, root: media)) } }
            let imported = try await Task.detached {
                try SceneFileRepository.materialize(document, mediaDirectory: media, id: id)
            }.value
            self.scenes[self.sceneIndex].layers = await self.renderer.read(self.scene.layers)
            try await self.renderer.install(imported, mediaDirectory: media)
            self.scenes.append(imported)
            committed = true
            self.selectedSceneID = imported.id
            self.selectedObjectID = nil
        }
    }

    func setEffect(_ value: VideoEffectItem) {
        Task { await renderer.setEffect(value) }
    }
}
