import Darwin
import Foundation

struct VQMetrixError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// One transfer per instance. Delegate callbacks are serial; task registration and cancellation share a short lock.
final class VQMetrixTransfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var response = Data()
    private var continuation: CheckedContinuation<UUID, Error>?
    private var uploadTask: URLSessionUploadTask?
    private var isCancelled = false

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard response.count + data.count <= 65_536 else { dataTask.cancel(); return }
        response.append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        uploadTask = nil
        lock.unlock()
        guard let continuation else { return }
        if let error { continuation.resume(throwing: error); return }
        guard let http = task.response as? HTTPURLResponse, [200, 201, 202].contains(http.statusCode) else {
            let status = (task.response as? HTTPURLResponse)?.statusCode ?? 0
            continuation.resume(throwing: VQMetrixError(message: String(localized: "Receiver returned HTTP \(status). Check reception and the connection code.")))
            return
        }
        struct Receipt: Decodable { let jobId: UUID }
        guard let receipt = try? JSONDecoder().decode(Receipt.self, from: response) else {
            continuation.resume(throwing: VQMetrixError(message: String(localized: "Invalid receiver receipt."))); return
        }
        continuation.resume(returning: receipt.jobId)
    }

    func send(file: URL, endpoint: URL, code: String, id: UUID) async throws -> UUID {
        try Task.checkCancellation()
        // Resolve .local names once and pin HTTP to the validated LAN address.
        let endpoint = try Self.resolvedEndpoint(endpoint, resolver: Self.resolveLocalName)
        try Task.checkCancellation()
        var request = URLRequest(url: endpoint.appendingPathComponent("api/v1/runs"))
        request.httpMethod = "POST"
        request.setValue("application/zip", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(code)", forHTTPHeaderField: "Authorization")
        request.setValue("1", forHTTPHeaderField: "X-VQMetrix-Protocol")
        request.setValue(id.uuidString, forHTTPHeaderField: "Idempotency-Key")
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 512 * 1024 * 1024 else { throw VQMetrixError(message: String(localized: "Package exceeds the receiver's 512 MiB limit.")) }
        request.setValue(String(size), forHTTPHeaderField: "Content-Length")
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 180
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        if endpoint.scheme == "http" { config.connectionProxyDictionary = [:] }
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                start(session: session, request: request, file: file, continuation: continuation)
            }
        } onCancel: {
            self.cancel()
        }
    }

    private func start(session: URLSession, request: URLRequest, file: URL, continuation: CheckedContinuation<UUID, Error>) {
        lock.lock()
        guard !isCancelled else {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return
        }
        self.continuation = continuation
        let task = session.uploadTask(with: request, fromFile: file)
        uploadTask = task
        lock.unlock()
        task.resume()
    }

    private func cancel() {
        lock.lock()
        isCancelled = true
        let task = uploadTask
        lock.unlock()
        task?.cancel()
    }

    static func endpoint(_ value: String) throws -> URL {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let hostname = url.host(percentEncoded: false), !hostname.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.port.map({ (1...65535).contains($0) }) ?? true,
              ["", "/"].contains(url.path), var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw VQMetrixError(message: String(localized: "Enter an HTTP or HTTPS base URL with a valid port and no credentials, path, or query."))
        }
        if scheme == "http" {
            let host = unbracket(hostname).lowercased()
            guard host == "localhost" || host.hasSuffix(".local") || host.hasSuffix(".local.") || isLocalAddress(host) else {
                throw VQMetrixError(message: String(localized: "HTTP requires a local network IP address or .local name. Use HTTPS for public receivers."))
            }
        }
        components.scheme = scheme
        guard let endpoint = components.url else { throw VQMetrixError(message: String(localized: "Invalid receiver URL.")) }
        return endpoint
    }

    static func resolvedEndpoint(_ value: URL, resolver: (String) throws -> [String]) throws -> URL {
        let url = try endpoint(value.absoluteString)
        guard url.scheme == "http", let hostname = url.host(percentEncoded: false) else { return url }
        let host = unbracket(hostname).lowercased()
        let addresses: [String]
        if host == "localhost" { addresses = ["127.0.0.1"] }
        else if isLocalAddress(host) { return url }
        else {
            do { addresses = try resolver(host) }
            catch {
                try Task.checkCancellation()
                throw error
            }
        }
        try Task.checkCancellation()
        guard !addresses.isEmpty, addresses.allSatisfy(isLocalAddress),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw VQMetrixError(message: String(localized: "The HTTP receiver must resolve only to local network addresses."))
        }
        // Prefer IPv4 where both families are advertised; preserve IPv6 scope identifiers.
        let address = addresses.first(where: { !$0.contains(":") }) ?? addresses[0]
        components.host = address.contains(":") ? "[\(address)]" : address
        guard let endpoint = components.url else { throw VQMetrixError(message: String(localized: "Invalid resolved receiver URL.")) }
        return endpoint
    }

    private static func resolveLocalName(_ host: String) throws -> [String] {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let first = result else {
            throw VQMetrixError(message: String(localized: "Cannot resolve the local receiver. Check its address and that reception is running."))
        }
        defer { freeaddrinfo(first) }
        var addresses: [String] = []
        var current: UnsafeMutablePointer<addrinfo>? = first
        while let entry = current {
            let info = entry.pointee
            if info.ai_family == AF_INET || info.ai_family == AF_INET6, let address = info.ai_addr {
                var name = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                guard getnameinfo(address, info.ai_addrlen, &name, socklen_t(name.count), nil, 0, NI_NUMERICHOST) == 0 else {
                    throw VQMetrixError(message: String(localized: "Cannot read the local receiver address."))
                }
                addresses.append(String(cString: name))
            }
            current = info.ai_next
        }
        return addresses
    }

    private static func unbracket(_ host: String) -> String {
        host.hasPrefix("[") && host.hasSuffix("]") ? String(host.dropFirst().dropLast()) : host
    }

    private static func isLocalAddress(_ value: String) -> Bool {
        let host = unbracket(value).split(separator: "%", maxSplits: 1).first.map(String.init) ?? ""
        var ipv4 = in_addr()
        if inet_pton(AF_INET, host, &ipv4) == 1 { return isLocalIPv4(UInt32(bigEndian: ipv4.s_addr)) }
        var ipv6 = in6_addr()
        guard inet_pton(AF_INET6, host, &ipv6) == 1 else { return false }
        let bytes = withUnsafeBytes(of: &ipv6) { Array($0) }
        if bytes.prefix(10).allSatisfy({ $0 == 0 }), bytes[10] == 255, bytes[11] == 255 {
            let address = bytes.suffix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            return isLocalIPv4(address)
        }
        return (bytes.prefix(15).allSatisfy({ $0 == 0 }) && bytes[15] == 1) ||
            bytes[0] & 0xfe == 0xfc || (bytes[0] == 0xfe && bytes[1] & 0xc0 == 0x80)
    }

    private static func isLocalIPv4(_ value: UInt32) -> Bool {
        value >> 24 == 10 || value >> 24 == 127 || value >> 20 == 0xac1 ||
            value >> 16 == 0xc0a8 || value >> 16 == 0xa9fe
    }
}
