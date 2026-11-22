import Foundation
import zlib

/// A portable scene file: ZIP entries `scene.json`, `manifest.json`, and `media/<filename>`.
/// The JSON uses the public ScreenObjectSnapshot wire format on Apple and Android.
public struct SceneArchive: Sendable {
    public enum Error: Swift.Error { case invalidArchive, unsupportedVersion, invalidResource, sizeLimitExceeded }
    public static let maximumResourceBytes = 128 * 1024 * 1024
    public let snapshot: ScreenObjectSnapshot
    public let resources: [String: Data]

    public init(snapshot: ScreenObjectSnapshot, resources: [String: Data] = [:]) throws {
        guard resources.count <= 256, resources.keys.allSatisfy(Self.isResourceName) else { throw Error.invalidResource }
        guard resources.values.reduce(0, { $0 + $1.count }) <= Self.maximumResourceBytes else { throw Error.sizeLimitExceeded }
        func portable(_ node: ScreenObjectSnapshot) -> ScreenObjectSnapshot {
            var elements = node.elements
            if node.type == "image" || node.type == "asset", let source = elements["source"], let url = URL(string: source), url.isFileURL,
               resources[url.lastPathComponent] != nil {
                elements["source"] = "media/" + url.lastPathComponent
            }
            return ScreenObjectSnapshot(type: node.type, id: node.id, size: node.size, isVisible: node.isVisible,
                layoutMargin: node.layoutMargin, horizontalAlignment: node.horizontalAlignment, verticalAlignment: node.verticalAlignment,
                elements: elements, children: node.children.map(portable), cornerRadius: node.cornerRadius)
        }
        let snapshot = portable(snapshot)
        func validate(_ node: ScreenObjectSnapshot) throws {
            if node.type == "image" || node.type == "asset" {
                let source = node.elements["source"] ?? ""
                if !(node.type == "image" && source.hasPrefix("data:")) {
                    guard source.hasPrefix("media/"), Self.isResourceName(String(source.dropFirst(6))),
                        resources[String(source.dropFirst(6))] != nil
                    else { throw Error.invalidResource }
                }
            }
            for child in node.children { try validate(child) }
        }
        try validate(snapshot)
        self.snapshot = snapshot
        self.resources = resources
    }

    /// Reads a portable ZIP, or a standalone snapshot JSON when no media files are required.
    public init(data: Data) throws {
        if data.prefix(2) != Data([0x50, 0x4b]) {
            guard data.count <= 4 * 1024 * 1024 else { throw Error.sizeLimitExceeded }
            try self.init(snapshot: JSONDecoder().decode(ScreenObjectSnapshot.self, from: data))
            return
        }
        let files = try SceneZIP.read(data)
        guard let json = files["scene.json"], json.count <= 4 * 1024 * 1024 else { throw Error.invalidArchive }
        if let manifest = files["manifest.json"] {
            guard manifest.count <= 65_536 else { throw Error.invalidArchive }
            let header = try JSONDecoder().decode(Manifest.self, from: manifest)
            guard header.format == "haishinkit.scene", header.version == 1 else { throw Error.unsupportedVersion }
        }
        var resources: [String: Data] = [:]
        for (path, contents) in files where path != "scene.json" && path != "manifest.json" {
            guard path.hasPrefix("media/"), Self.isResourceName(String(path.dropFirst(6))) else { throw Error.invalidResource }
            resources[String(path.dropFirst(6))] = contents
        }
        try self.init(snapshot: JSONDecoder().decode(ScreenObjectSnapshot.self, from: json), resources: resources)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let json = try encoder.encode(snapshot)
        guard json.count <= 4 * 1024 * 1024 else { throw Error.sizeLimitExceeded }
        var files = ["scene.json": json, "manifest.json": try encoder.encode(Manifest(format: "haishinkit.scene", version: 1))]
        for (name, data) in resources { files["media/" + name] = data }
        return try SceneZIP.write(files)
    }

    private struct Manifest: Codable {
        let format: String
        let version: Int
    }
    private static func isResourceName(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".." && !value.contains("/") && !value.contains("\\") && !value.contains(":")
            && !value.contains("\0")
    }
}

/// Store output keeps already-compressed images/video cheap; input also supports Java ZIP's DEFLATE/data descriptors.
private enum SceneZIP {
    private static let maximumBytes = SceneArchive.maximumResourceBytes + 8 * 1024 * 1024

    static func write(_ files: [String: Data]) throws -> Data {
        var output = Data()
        var central = Data()
        for name in files.keys.sorted() {
            let bytes = files[name]!
            let filename = Data(name.utf8)
            guard filename.count <= Int(UInt16.max), output.count <= maximumBytes else { throw SceneArchive.Error.sizeLimitExceeded }
            let offset = UInt32(output.count)
            let crc = checksum(bytes)
            output.put32(0x0403_4b50)
            output.put16(20)
            output.put16(0x0800)
            output.put16(0)
            output.put16(0)
            output.put16(0)
            output.put32(crc)
            output.put32(UInt32(bytes.count))
            output.put32(UInt32(bytes.count))
            output.put16(UInt16(filename.count))
            output.put16(0)
            output.append(filename)
            output.append(bytes)
            central.put32(0x0201_4b50)
            central.put16(20)
            central.put16(20)
            central.put16(0x0800)
            central.put16(0)
            central.put16(0)
            central.put16(0)
            central.put32(crc)
            central.put32(UInt32(bytes.count))
            central.put32(UInt32(bytes.count))
            central.put16(UInt16(filename.count))
            central.put16(0)
            central.put16(0)
            central.put16(0)
            central.put16(0)
            central.put32(0)
            central.put32(offset)
            central.append(filename)
        }
        let offset = UInt32(output.count)
        output.append(central)
        output.put32(0x0605_4b50)
        output.put16(0)
        output.put16(0)
        output.put16(UInt16(files.count))
        output.put16(UInt16(files.count))
        output.put32(UInt32(central.count))
        output.put32(offset)
        output.put16(0)
        guard output.count <= maximumBytes else { throw SceneArchive.Error.sizeLimitExceeded }
        return output
    }

    static func read(_ data: Data) throws -> [String: Data] {
        guard data.count >= 22, data.count <= maximumBytes else { throw SceneArchive.Error.sizeLimitExceeded }
        var end: Int?
        for position in stride(from: data.count - 22, through: max(0, data.count - 65_557), by: -1) {
            if data.get32(position) == 0x0605_4b50, position + 22 + Int(data.get16(position + 20)) == data.count {
                end = position
                break
            }
        }
        guard let end, data.get16(end + 4) == 0, data.get16(end + 6) == 0,
            data.get16(end + 8) == data.get16(end + 10)
        else { throw SceneArchive.Error.invalidArchive }
        let count = Int(data.get16(end + 10))
        let centralSize = Int(data.get32(end + 12))
        let centralStart = Int(data.get32(end + 16))
        guard count <= 260, centralStart + centralSize == end else { throw SceneArchive.Error.invalidArchive }
        var cursor = centralStart
        var files: [String: Data] = [:]
        var total = 0
        for _ in 0..<count {
            guard cursor + 46 <= end, data.get32(cursor) == 0x0201_4b50 else { throw SceneArchive.Error.invalidArchive }
            let flags = data.get16(cursor + 8)
            let method = data.get16(cursor + 10)
            let crc = data.get32(cursor + 16)
            let packed = Int(data.get32(cursor + 20))
            let size = Int(data.get32(cursor + 24))
            let nameSize = Int(data.get16(cursor + 28))
            let extra = Int(data.get16(cursor + 30))
            let comment = Int(data.get16(cursor + 32))
            let local = Int(data.get32(cursor + 42))
            let next = cursor + 46 + nameSize + extra + comment
            total += size
            guard flags & 1 == 0, method == 0 || method == 8, next <= end, total <= maximumBytes,
                data.get16(cursor + 34) == 0, data.get32(cursor + 38) >> 16 & 0xf000 != 0xa000,
                let name = String(data: data.segment(cursor + 46, nameSize), encoding: .utf8),
                !name.hasPrefix("/"), !name.contains("\\"), !name.contains("\0"),
                !name.split(separator: "/").contains(".."), files[name] == nil,
                local + 30 <= centralStart, data.get32(local) == 0x0403_4b50, data.get16(local + 6) & 1 == 0,
                data.get16(local + 8) == method
            else { throw SceneArchive.Error.invalidArchive }
            let localName = Int(data.get16(local + 26))
            let localExtra = Int(data.get16(local + 28))
            let payload = local + 30 + localName + localExtra
            guard payload + packed <= centralStart, localName == nameSize,
                data.segment(local + 30, localName) == Data(name.utf8)
            else { throw SceneArchive.Error.invalidArchive }
            let compressed = data.segment(payload, packed)
            let bytes: Data
            if method == 0 {
                guard size == packed else { throw SceneArchive.Error.invalidArchive }
                bytes = compressed
            } else {
                bytes = try inflate(compressed, size: size)
            }
            guard checksum(bytes) == crc else { throw SceneArchive.Error.invalidArchive }
            if name.hasSuffix("/") {
                guard size == 0 else { throw SceneArchive.Error.invalidArchive }
            } else {
                files[name] = bytes
            }
            cursor = next
        }
        guard cursor == end else { throw SceneArchive.Error.invalidArchive }
        return files
    }

    private static func checksum(_ data: Data) -> UInt32 {
        data.withUnsafeBytes { UInt32(crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt(data.count))) }
    }

    private static func inflate(_ data: Data, size: Int) throws -> Data {
        var stream = z_stream()
        guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw SceneArchive.Error.invalidArchive
        }
        defer { inflateEnd(&stream) }
        var output = Data(count: max(1, size))
        let status = data.withUnsafeBytes { input in
            output.withUnsafeMutableBytes { destination in
                stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: Bytef.self).baseAddress)
                stream.avail_in = uInt(data.count)
                stream.next_out = destination.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uInt(destination.count)
                return zlib.inflate(&stream, Z_FINISH)
            }
        }
        guard status == Z_STREAM_END, stream.total_out == size, stream.total_in == data.count else {
            throw SceneArchive.Error.invalidArchive
        }
        return Data(output.prefix(size))
    }
}

extension Data {
    fileprivate mutating func put16(_ value: UInt16) {
        var value = value.littleEndian
        Swift.withUnsafeBytes(of: &value) { append(contentsOf: $0) }
    }
    fileprivate mutating func put32(_ value: UInt32) {
        var value = value.littleEndian
        Swift.withUnsafeBytes(of: &value) { append(contentsOf: $0) }
    }
    fileprivate func get16(_ offset: Int) -> UInt16 {
        withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self).littleEndian }
    }
    fileprivate func get32(_ offset: Int) -> UInt32 {
        withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self).littleEndian }
    }
    fileprivate func segment(_ offset: Int, _ count: Int) -> Data { Data(dropFirst(offset).prefix(count)) }
}
