import AVFoundation
import CoreImage
import HaishinKit
import SwiftUI

struct StudioLayer: Codable, Identifiable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case input, text, image, video
        var title: String {
            switch self {
            case .input: "Capture input"
            case .text: "Text"
            case .image: "Image"
            case .video: "Video"
            }
        }
        var symbol: String {
            switch self {
            case .input: "video"
            case .text: "textformat"
            case .image: "photo"
            case .video: "film"
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
}

struct StudioScene: Codable, Identifiable, Equatable, Sendable {
    var id = UUID().uuidString
    var name: String
    var layers: [StudioLayer]
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

    func install(_ scene: StudioScene, mediaDirectory: URL) async throws {
        let screen = mixer.screen
        var replacement: [String: ScreenObject] = [:]
        var replacementEffects: [String: VideoEffect] = [:]
        do {
            for layer in scene.layers {
                let object: ScreenObject
                switch layer.kind {
                case .input:
                    let video = VideoScreenObject(id: layer.id)
                    video.track = 0
                    video.videoGravity = .resizeAspectFill
                    if let effect = effect.makeVideoEffect() {
                        _ = video.registerVideoEffect(effect)
                        replacementEffects[layer.id] = effect
                    }
                    object = video
                case .text:
                    object = TextScreenObject(id: layer.id)
                case .image:
                    let image = ImageScreenObject(id: layer.id)
                    guard let media = layer.media,
                        let source = CIImage(contentsOf: mediaDirectory.appendingPathComponent(media))
                    else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    image.ciImage = source
                    object = image
                case .video:
                    guard let media = layer.media else { throw CocoaError(.fileNoSuchFile) }
                    let video = AssetScreenObject(id: layer.id)
                    video.videoGravity = .resizeAspectFill
                    video.isLooping = true
                    try video.startReading(AVURLAsset(url: mediaDirectory.appendingPathComponent(media)))
                    guard video.isReading else { throw CocoaError(.fileReadCorruptFile) }
                    object = video
                }
                replacement[layer.id] = object
                apply(layer, to: object)
            }
        } catch {
            replacement.values.forEach { ($0 as? AssetScreenObject)?.cancelReading() }
            throw error
        }
        // Replace the scene in one rendering-actor turn, after every source is ready.
        for object in objects.values {
            (object as? AssetScreenObject)?.cancelReading()
            screen.removeChild(object)
        }
        let snapshot = ScreenObjectSnapshotFactory().make(screen)
        for child in snapshot.children where !child.id.hasPrefix("example-overlay-") {
            screen.findById(child.id)?.isVisible = false
        }
        screen.size = CGSize(width: 1280, height: 720)
        screen.backgroundColor = NSColor.black.cgColor
        objects = replacement
        effects = replacementEffects
        for layer in scene.layers { try screen.addChild(objects[layer.id]) }
    }

    func update(_ layer: StudioLayer) async {
        guard let object = objects[layer.id] else { return }
        apply(layer, to: object)
    }

    private func apply(_ layer: StudioLayer, to object: ScreenObject) {
        object.isVisible = layer.visible
        object.size = CGSize(width: layer.width, height: layer.height)
        object.horizontalAlignment = .left
        object.verticalAlignment = .top
        object.layoutMargin = .init(top: layer.y, left: layer.x, bottom: 0, right: 0)
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
            updated.visible = object.isVisible
            updated.width = object.size.width
            updated.height = object.size.height
            updated.x = object.layoutMargin.left
            updated.y = object.layoutMargin.top
            if let text = object as? TextScreenObject {
                updated.text = text.string
                updated.fontSize = Double(text.elements["fontSize"] ?? "40") ?? 40
                updated.color = text.elements["color"] ?? "#FFFFFFFF"
            }
            return updated
        }
    }

    func suspend() {
        objects.values.forEach { ($0 as? AssetScreenObject)?.cancelReading() }
    }

    func setEffect(_ value: VideoEffectItem) {
        effect = value
        for (id, object) in objects {
            guard let video = object as? VideoScreenObject else { continue }
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
    private let defaults: UserDefaults
    private static let storageKey = "macos.studio.scenes.v1"
    let mediaDirectory: URL

    var scene: StudioScene { scenes.first { $0.id == selectedSceneID } ?? scenes[0] }
    var selectedLayer: StudioLayer? { scene.layers.first { $0.id == selectedObjectID } }

    init(mixer: MediaMixer, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        renderer = StudioSceneRenderer(mixer: mixer)
        mediaDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HaishinKit/SceneMedia", isDirectory: true)
        let saved = defaults.data(forKey: Self.storageKey).flatMap {
            try? JSONDecoder().decode([StudioScene].self, from: $0)
        }
        let scenes = saved.flatMap { $0.isEmpty ? nil : $0 } ?? [.initial()]
        self.scenes = scenes
        selectedSceneID = defaults.string(forKey: Self.storageKey + ".selection") ?? scenes[0].id
        if !scenes.contains(where: { $0.id == selectedSceneID }) { selectedSceneID = scenes[0].id }
    }

    func start() async {
        guard !started else { return }
        started = true
        busy = true
        do { try await renderer.install(scene, mediaDirectory: mediaDirectory) } catch {
            errorMessage = "Could not restore this scene: \(error.localizedDescription)"
        }
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
            save()
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
    private func save() {
        do {
            defaults.set(try JSONEncoder().encode(scenes), forKey: Self.storageKey)
            defaults.set(selectedSceneID, forKey: Self.storageKey + ".selection")
        } catch { errorMessage = error.localizedDescription }
    }

    private func perform(_ action: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true
        operation = Task {
            defer { busy = false }
            do {
                try await action()
                save()
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
            scene.layers = scene.layers.map { layer in
                var copy = layer
                copy.id = "example-overlay-" + UUID().uuidString
                return copy
            }
            try await self.renderer.install(scene, mediaDirectory: self.mediaDirectory)
            self.scenes.append(scene)
            self.selectedSceneID = scene.id
            self.selectedObjectID = nil
        }
    }

    func renameScene(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy, !trimmed.isEmpty else { return }
        scenes[sceneIndex].name = trimmed
        save()
    }

    func deleteScene() {
        guard scenes.count > 1 else { return }
        perform {
            let oldID = self.selectedSceneID
            let next = self.scenes.first { $0.id != oldID }!
            try await self.renderer.install(next, mediaDirectory: self.mediaDirectory)
            self.scenes.removeAll { $0.id == oldID }
            self.selectedSceneID = next.id
            self.selectedObjectID = nil
        }
    }

    func addLayer(_ kind: StudioLayer.Kind, file: URL? = nil) {
        perform {
            var layer = StudioLayer(kind: kind, name: kind.title)
            switch kind {
            case .input:
                layer.width = 640
                layer.height = 360
            case .text:
                layer.width = 520
                layer.height = 100
            case .image, .video:
                guard let file else { return }
                let access = file.startAccessingSecurityScopedResource()
                defer { if access { file.stopAccessingSecurityScopedResource() } }
                try FileManager.default.createDirectory(
                    at: self.mediaDirectory, withIntermediateDirectories: true)
                let filename = UUID().uuidString + "." + file.pathExtension
                let destination = self.mediaDirectory.appendingPathComponent(filename)
                try await Task.detached(priority: .userInitiated) {
                    try FileManager.default.copyItem(at: file, to: destination)
                }.value
                layer.media = filename
                layer.name = file.deletingPathExtension().lastPathComponent
                let sourceSize: CGSize
                if kind == .image {
                    guard
                        let image = CIImage(contentsOf: self.mediaDirectory.appendingPathComponent(filename))
                    else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    sourceSize = image.extent.size
                } else {
                    let asset = AVURLAsset(url: self.mediaDirectory.appendingPathComponent(filename))
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
        }
    }

    func updateLayer(_ layer: StudioLayer) {
        guard !busy, let index = scene.layers.firstIndex(where: { $0.id == layer.id }) else { return }
        perform {
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
            var copy = original
            copy.id = "example-overlay-" + UUID().uuidString
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

    func setEffect(_ value: VideoEffectItem) {
        Task { await renderer.setEffect(value) }
    }
}
