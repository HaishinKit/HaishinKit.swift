import AVFoundation
import CryptoKit
import Foundation
import HaishinKit
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let haishinKitScene = UTType(exportedAs: "com.haishinkit.scene", conformingTo: .zip)
}

struct SceneFileError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// The package contains an ordinary ScreenObjectSnapshot JSON and its local resources.
struct SceneFileDocument: FileDocument, Sendable {
    static var readableContentTypes: [UTType] { [.haishinKitScene, .json] }
    static var writableContentTypes: [UTType] { [.haishinKitScene] }
    let snapshot: ScreenObjectSnapshot
    let resources: [String: Data]

    init(snapshot: ScreenObjectSnapshot, resources: [String: Data]) throws {
        try Self.validate(snapshot, resources: resources)
        self.snapshot = snapshot
        self.resources = resources
    }

    init(configuration: ReadConfiguration) throws {
        try self.init(wrapper: configuration.file)
    }

    init(wrapper: FileWrapper) throws {
        guard wrapper.isRegularFile, let data = wrapper.regularFileContents else {
            throw SceneFileError(message: "Open a portable .haishinscene ZIP or snapshot JSON.")
        }
        let archive = try SceneFile(data: data)
        try self.init(snapshot: archive.snapshot, resources: archive.resources)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { try wrapper() }

    func wrapper() throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try SceneFile(snapshot: snapshot, resources: resources).encoded())
    }

    static func read(_ url: URL) throws -> Self { try Self(wrapper: FileWrapper(url: url, options: .immediate)) }

    static func safeFilename(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\\") && !name.contains(":")
            && name.unicodeScalars.allSatisfy { $0.value != 0 }
    }

    static func mediaName(_ source: String) throws -> String {
        guard source.hasPrefix("media/"), safeFilename(String(source.dropFirst(6))) else {
            throw SceneFileError(message: "Media references must point to files inside this scene's media folder.")
        }
        return String(source.dropFirst(6))
    }

    static func validate(_ root: ScreenObjectSnapshot, resources: [String: Data], allowMissingResources: Bool = false) throws {
        guard Set(resources.keys.map { $0.precomposedStringWithCanonicalMapping.lowercased().uppercased().lowercased().precomposedStringWithCanonicalMapping }).count == resources.count,
            resources.keys.allSatisfy(safeFilename), resources.count <= 256,
            resources.values.reduce(0, { $0 + $1.count }) <= SceneFile.maximumResourceBytes
        else {
            throw SceneFileError(message: "Scene resources are invalid or exceed 128 MB.")
        }
        guard ["screen", "container"].contains(root.type), !root.id.isEmpty,
            (1...8192).contains(root.size.width), (1...8192).contains(root.size.height)
        else {
            throw SceneFileError(message: "Use a screen or container with a canvas between 1 and 8192 pixels.")
        }
        var ids = Set<String>()
        var count = 0
        func visit(_ node: ScreenObjectSnapshot, depth: Int) throws {
            count += 1
            guard depth <= 16, count <= 256, !node.id.isEmpty, ids.insert(node.id).inserted,
                !node.type.isEmpty,
                (node.cornerRadius ?? 0).isFinite, (0...8192).contains(node.cornerRadius ?? 0),
                (0...8192).contains(node.size.width), (0...8192).contains(node.size.height),
                (0...2).contains(node.horizontalAlignment), (0...2).contains(node.verticalAlignment),
                [node.layoutMargin.top, node.layoutMargin.left, node.layoutMargin.bottom, node.layoutMargin.right].allSatisfy({
                    (-8192...8192).contains($0)
                })
            else {
                throw SceneFileError(message: "The snapshot contains unsupported nodes, duplicate identifiers, or invalid layout values.")
            }
            if node.type == "text" {
                guard let size = Double(node.elements["fontSize"] ?? "32"), size.isFinite, (1...1024).contains(size) else {
                    throw SceneFileError(message: "A text object's font size is invalid.")
                }
            }
            if node.type == "video", UInt8(node.elements["track"] ?? "0") == nil {
                throw SceneFileError(message: "A capture input track is invalid.")
            }
            if node.type == "image" || node.type == "asset" {
                let source = node.elements["source"] ?? ""
                if !(node.type == "image" && source.hasPrefix("data:")) {
                    let name = try mediaName(source)
                    guard allowMissingResources || resources[name] != nil else {
                        throw SceneFileError(message: "Missing scene media: \(name)")
                    }
                }
            }
            if ["video", "text", "image", "asset"].contains(node.type), !node.children.isEmpty {
                throw SceneFileError(message: "Only containers can contain child objects.")
            }
            for child in node.children { try visit(child, depth: depth + 1) }
        }
        try visit(root, depth: 0)
    }
}

/// Converts the editor's transient inspector state to the library's file format.
enum SceneSnapshotCodec {
    static func encode(_ snapshot: ScreenObjectSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try encoder.encode(snapshot)
    }

    static func node(_ layer: StudioLayer) throws -> ScreenObjectSnapshot {
        let basis = try layer.snapshotData.map { try JSONDecoder().decode(ScreenObjectSnapshot.self, from: $0) }
        let type: String
        switch layer.kind {
        case .input: type = "video"
        case .text: type = "text"
        case .image: type = "image"
        case .video: type = "asset"
        case .group: type = "container"
        case .unsupported: type = basis?.type ?? "unsupported"
        }
        if layer.kind == .unsupported, let basis { return basis }
        guard [layer.width, layer.height].allSatisfy({ $0.isFinite && (0...8192).contains($0) }),
            layer.absoluteLayout == false || [layer.x, layer.y].allSatisfy({ $0.isFinite && (-8192...8192).contains($0) }) else {
            throw SceneFileError(message: "Object geometry is outside the scene file limits.")
        }
        var elements = basis?.elements ?? [:]
        elements["name"] = layer.name
        switch layer.kind {
        case .input:
            if elements["track"] == nil { elements["track"] = "0" }
            if basis == nil, elements["videoGravity"] == nil { elements["videoGravity"] = "resizeAspectFill" }
        case .text: elements.merge(["value": layer.text, "fontSize": String(layer.fontSize), "color": layer.color]) { _, value in value }
        case .image, .video:
            if let media = layer.media { elements["source"] = "media/" + media }
            if layer.kind == .video, basis == nil {
                elements["looping"] = "true"
                elements["videoGravity"] = "resizeAspectFill"
            }
        case .group, .unsupported: break
        }
        return ScreenObjectSnapshot(
            type: type, id: layer.id, size: .init(width: Int(layer.width), height: Int(layer.height)), isVisible: layer.visible,
            layoutMargin: layer.absoluteLayout == false ? (basis?.layoutMargin ?? .init()) : .init(top: Int(layer.y), left: Int(layer.x)),
            horizontalAlignment: layer.absoluteLayout == false ? (basis?.horizontalAlignment ?? 0) : 0,
            verticalAlignment: layer.absoluteLayout == false ? (basis?.verticalAlignment ?? 0) : 0,
            elements: elements, children: basis?.children ?? [], cornerRadius: basis?.cornerRadius)
    }

    static func snapshot(_ scene: StudioScene) throws -> ScreenObjectSnapshot {
        let basis = try scene.snapshotData.map { try JSONDecoder().decode(ScreenObjectSnapshot.self, from: $0) }
        var elements = basis?.elements ?? [:]
        elements["name"] = scene.name
        return ScreenObjectSnapshot(
            type: basis?.type ?? "container", id: scene.id,
            size: .init(width: scene.canvasWidth ?? 1280, height: scene.canvasHeight ?? 720),
            isVisible: scene.rootVisible ?? basis?.isVisible ?? true, layoutMargin: basis?.layoutMargin ?? .init(),
            horizontalAlignment: basis?.horizontalAlignment ?? 0, verticalAlignment: basis?.verticalAlignment ?? 0,
            elements: elements, children: try scene.layers.map(node), cornerRadius: basis?.cornerRadius)
    }

    static func scene(_ snapshot: ScreenObjectSnapshot) throws -> StudioScene {
        let layers = try snapshot.children.map { node -> StudioLayer in
            let kind: StudioLayer.Kind
            switch node.type {
            case "video": kind = .input
            case "text": kind = .text
            case "image": kind = .image
            case "asset": kind = .video
            case "screen", "container": kind = .group
            default: kind = .unsupported
            }
            return StudioLayer(
                id: node.id, kind: kind, name: node.elements["name"] ?? (kind == .unsupported ? "Unsupported (\(node.type))" : kind.title),
                x: Double(node.layoutMargin.left), y: Double(node.layoutMargin.top), width: Double(node.size.width),
                height: Double(node.size.height),
                visible: node.isVisible, text: node.elements["value"] ?? "", fontSize: Double(node.elements["fontSize"] ?? "32") ?? 32,
                color: node.elements["color"] ?? "#FFFFFFFF",
                media: [.image, .video].contains(kind) && (node.elements["source"] ?? "").hasPrefix("media/")
                    ? try SceneFileDocument.mediaName(node.elements["source"] ?? "") : nil,
                snapshotData: try encode(node), absoluteLayout: false)
        }
        return StudioScene(
            id: snapshot.id, name: snapshot.elements["name"] ?? "Scene", layers: layers,
            canvasWidth: snapshot.size.width, canvasHeight: snapshot.size.height, snapshotData: try encode(snapshot),
            rootVisible: snapshot.isVisible)
    }

    static func map(_ node: ScreenObjectSnapshot, transform: (ScreenObjectSnapshot) throws -> [String: String]) rethrows
        -> ScreenObjectSnapshot
    {
        try ScreenObjectSnapshot(
            type: node.type, id: node.id, size: node.size, isVisible: node.isVisible, layoutMargin: node.layoutMargin,
            horizontalAlignment: node.horizontalAlignment, verticalAlignment: node.verticalAlignment,
            elements: transform(node), children: node.children.map { try map($0, transform: transform) }, cornerRadius: node.cornerRadius)
    }

    static func sources(_ node: ScreenObjectSnapshot) -> Set<String> {
        var result = Set<String>()
        if ["image", "asset"].contains(node.type), let source = node.elements["source"], source.hasPrefix("media/") {
            result.insert(String(source.dropFirst(6)))
        }
        for child in node.children { result.formUnion(sources(child)) }
        return result
    }

    static func containsUnsupported(_ node: ScreenObjectSnapshot) -> Bool {
        !["screen", "container", "video", "text", "image", "asset"].contains(node.type)
            || node.children.contains(where: containsUnsupported)
    }

    static func duplicate(_ layer: StudioLayer) throws -> StudioLayer {
        func copy(_ node: ScreenObjectSnapshot) -> ScreenObjectSnapshot {
            ScreenObjectSnapshot(
                type: node.type, id: "example-overlay-" + UUID().uuidString, size: node.size,
                isVisible: node.isVisible, layoutMargin: node.layoutMargin, horizontalAlignment: node.horizontalAlignment,
                verticalAlignment: node.verticalAlignment, elements: node.elements, children: node.children.map(copy),
                cornerRadius: node.cornerRadius)
        }
        let cloned = copy(try node(layer))
        var layer = layer
        layer.id = cloned.id
        layer.snapshotData = try encode(cloned)
        return layer
    }
}

/// Files, rather than UserDefaults-encoded editor models, are the persisted scene data.
enum SceneFileRepository {
    private static let mediaLock = NSLock()
    static func key(_ id: String) -> String { SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined() }
    static func url(id: String, directory: URL) -> URL { directory.appendingPathComponent(key(id)).appendingPathExtension("json") }
    static func mediaURL(id: String, root: URL) -> URL { root.appendingPathComponent(key(id), isDirectory: true) }

    static func resources(id: String, mediaDirectory: URL, names: Set<String>? = nil) throws -> [String: Data] {
        let directory = mediaURL(id: id, root: mediaDirectory)
        guard FileManager.default.fileExists(atPath: directory.path) else { return [:] }
        var files: [String: Data] = [:]
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            if let names, !names.contains(url.lastPathComponent) { continue }
            guard SceneFileDocument.safeFilename(url.lastPathComponent) else { throw SceneFileError(message: "Invalid scene media name.") }
            files[url.lastPathComponent] = try Data(contentsOf: url, options: .mappedIfSafe)
        }
        return files
    }

    static func document(_ scene: StudioScene, mediaDirectory: URL) throws -> SceneFileDocument {
        let snapshot = try SceneSnapshotCodec.snapshot(scene)
        return try SceneFileDocument(
            snapshot: snapshot,
            resources: resources(
                id: scene.id, mediaDirectory: mediaDirectory,
                names: SceneSnapshotCodec.containsUnsupported(snapshot) ? nil : SceneSnapshotCodec.sources(snapshot)))
    }

    static func materialize(_ document: SceneFileDocument, mediaDirectory: URL, id: String? = nil, sceneDirectory: URL? = nil) throws -> StudioScene {
        mediaLock.lock()
        defer { mediaLock.unlock() }
        var scene = try SceneSnapshotCodec.scene(document.snapshot)
        if let id { scene.id = id }
        while FileManager.default.fileExists(atPath: mediaURL(id: scene.id, root: mediaDirectory).path)
            || sceneDirectory.map({ FileManager.default.fileExists(atPath: url(id: scene.id, directory: $0).path) }) == true {
            scene.id = UUID().uuidString
        }
        let directory = mediaURL(id: scene.id, root: mediaDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            for (name, data) in document.resources { try data.write(to: directory.appendingPathComponent(name), options: .atomic) }
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
        return scene
    }

    static func copyMedia(from sourceID: String, to destinationID: String, root: URL) throws {
        let source = mediaURL(id: sourceID, root: root)
        let destination = mediaURL(id: destinationID, root: root)
        if FileManager.default.fileExists(atPath: source.path) { try FileManager.default.copyItem(at: source, to: destination) }
    }
}

/// Serializes in-process writers and rejects stale edits instead of overwriting another window.
final class SceneSaveSession: @unchecked Sendable {
    private static let lock = NSLock()
    private var diskVersions: [String: Data] = [:]
    private var snapshots: [String: Data] = [:]

    func read(_ url: URL, mediaDirectory: URL) throws -> StudioScene {
        try Self.lock.withLock {
            let key = url.standardizedFileURL.path
            let data = try Data(contentsOf: url)
            let snapshot = try JSONDecoder().decode(ScreenObjectSnapshot.self, from: data)
            try SceneFileDocument.validate(snapshot, resources: [:], allowMissingResources: true)
            let scene = try SceneSnapshotCodec.scene(snapshot)
            diskVersions[key] = data
            snapshots[key] = try SceneSnapshotCodec.encode(SceneSnapshotCodec.snapshot(scene))
            return scene
        }
    }

    func save(_ scenes: [StudioScene], directory: URL) throws {
        try Self.lock.withLock {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for scene in scenes {
                let url = SceneFileRepository.url(id: scene.id, directory: directory)
                let key = url.standardizedFileURL.path
                let snapshot = try SceneSnapshotCodec.snapshot(scene)
                try SceneFileDocument.validate(snapshot, resources: [:], allowMissingResources: true)
                let data = try SceneSnapshotCodec.encode(snapshot)
                guard snapshots[key] != data else { continue }
                guard (try? Data(contentsOf: url)) == diskVersions[key] else {
                    throw SceneFileError(message: "This scene was changed or deleted in another window. Reopen Publish before editing it.")
                }
                try data.write(to: url, options: .atomic)
                diskVersions[key] = data
                snapshots[key] = data
            }
        }
    }

    func delete(id: String, directory: URL, mediaDirectory: URL) throws {
        try Self.lock.withLock {
            let url = SceneFileRepository.url(id: id, directory: directory)
            let key = url.standardizedFileURL.path
            guard (try? Data(contentsOf: url)) == diskVersions[key] else {
                throw SceneFileError(message: "This scene was changed in another window. Reopen Publish before deleting it.")
            }
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            let media = SceneFileRepository.mediaURL(id: id, root: mediaDirectory)
            if FileManager.default.fileExists(atPath: media.path) { try FileManager.default.removeItem(at: media) }
            diskVersions[key] = nil
            snapshots[key] = nil
        }
    }
}
