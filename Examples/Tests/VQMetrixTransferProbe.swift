import Foundation

@main struct VQMetrixTransferProbe {
    static func main() async throws {
        guard CommandLine.arguments.count == 7 else { fatalError("Pass six local test server ports.") }
        let ports = CommandLine.arguments.dropFirst().map { Int($0)! }
        func url(_ index: Int) -> URL { URL(string: "http://127.0.0.1:\(ports[index])")! }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("vqmetrix-transfer-\(UUID().uuidString).zip")
        try Data(repeating: 42, count: 131_072).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let id = UUID(uuidString: "12345678-1234-1234-1234-123456789abc")!
        for _ in 0..<2 {
            let job = try await VQMetrixTransfer().send(file: file, endpoint: url(0), code: "1234", id: id)
            precondition(job == id)
        }
        print("PASS valid receipt and same-ID retry")
        for index in [1, 3] {
            do {
                _ = try await VQMetrixTransfer().send(file: file, endpoint: url(index), code: "1234", id: id)
                fatalError("Accepted an invalid, redirect, or oversized response")
            } catch { }
        }
        do {
            _ = try await VQMetrixTransfer().send(file: file, endpoint: url(2), code: "1234", id: id)
            fatalError("Followed a redirect")
        } catch let error as VQMetrixError {
            precondition(error.message.contains("HTTP 302"), error.message)
        }
        print("PASS invalid receipt, redirect, and oversized-response rejection")
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await VQMetrixTransfer().send(file: file, endpoint: url(0), code: "1234", id: id)
        }
        do { _ = try await cancelled.value; fatalError("Ignored cancellation") }
        catch is CancellationError { }
        let active = Task { try await VQMetrixTransfer().send(file: file, endpoint: url(4), code: "1234", id: id) }
        try await Task.sleep(for: .milliseconds(100))
        active.cancel()
        do { _ = try await active.value; fatalError("Ignored active cancellation") }
        catch { }
        for index in 0..<100 {
            let task = Task {
                try await VQMetrixTransfer().send(file: file, endpoint: URL(string: "http://127.0.0.1:1")!, code: "1234", id: id)
            }
            if index.isMultiple(of: 2) { await Task.yield() }
            task.cancel()
            do { _ = try await task.value; fatalError("Unexpected upload success") }
            catch { }
        }
        print("PASS cancellation before start, during a request, and 100 registration races")
        for host in ["127.0.0.1", "10.0.0.1", "172.16.0.1", "172.31.255.254", "192.168.1.2", "169.254.1.2", "[::1]", "[fd00::1]", "[fe80::1%25en0]", "[::ffff:192.168.1.2]"] {
            _ = try VQMetrixTransfer.endpoint("http://\(host):8787")
        }
        for value in ["http://example.com:8787", "http://8.8.8.8", "http://172.32.0.1", "http://[2001:4860:4860::8888]", "http://[::ffff:8.8.8.8]", "http://0.0.0.0", "http://[::]", "http://127.0.0.1:0", "http://127.0.0.1:65536", "http://user:pass@127.0.0.1", "http://127.0.0.1/path", "http://127.0.0.1?q=1"] {
            do { _ = try VQMetrixTransfer.endpoint(value); fatalError("Accepted unsafe URL: \(value)") }
            catch { }
        }
        let name = URL(string: "http://receiver.local:8787")!
        let cancelledLookup = Task {
            try VQMetrixTransfer.resolvedEndpoint(name) { _ in
                withUnsafeCurrentTask { $0?.cancel() }
                throw VQMetrixError(message: "Cannot resolve the local receiver.")
            }
        }
        do { _ = try await cancelledLookup.value; fatalError("Ignored lookup cancellation") }
        catch is CancellationError { }
        print("PASS lookup cancellation takes precedence over DNS errors")
        let local = try VQMetrixTransfer.resolvedEndpoint(name) { _ in ["192.168.1.2", "fd00::1"] }
        precondition(local.host == "192.168.1.2" && local.port == 8787)
        let scoped = try VQMetrixTransfer.resolvedEndpoint(name) { _ in ["fe80::1%en0"] }
        precondition(scoped.absoluteString.contains("fe80") && scoped.absoluteString.contains("en0"))
        for addresses in [[], [""], ["8.8.8.8"], ["192.168.1.2", "8.8.8.8"]] {
            do { _ = try VQMetrixTransfer.resolvedEndpoint(name) { _ in addresses }; fatalError("Accepted unsafe DNS result") }
            catch { }
        }
        let localhost = try VQMetrixTransfer.resolvedEndpoint(URL(string: "http://localhost:8787")!) { _ in fatalError("Resolved localhost") }
        precondition(localhost.host == "127.0.0.1")
        let secure = URL(string: "https://example.com:8787")!
        let https = try VQMetrixTransfer.resolvedEndpoint(secure) { _ in fatalError("Replaced HTTPS hostname") }
        precondition(https == secure)
        print("PASS LAN-only HTTP, validated .local address pinning, IPv4/IPv6 ranges, URL validation, and HTTPS hostname preservation")
    }
}
