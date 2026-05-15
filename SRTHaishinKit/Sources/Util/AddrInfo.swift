import Foundation
import libsrt

struct AddrInfo {
    enum Error: Swift.Error {
        case failedToGetaddrinfo(_ code: Int)
        case failedToResolve
    }

    let host: String
    let port: Int

    @discardableResult
    func resolve<R>(_ flags: Int32, lambda: (UnsafePointer<sockaddr>, Int32) throws -> R?) throws -> R {
        var hints = addrinfo(
            ai_flags: flags,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_DGRAM,
            ai_protocol: 0,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var result: UnsafeMutablePointer<addrinfo>?
        let rv = getaddrinfo(host, String(port), &hints, &result)
        guard rv == 0 else {
            throw Error.failedToGetaddrinfo(Int(rv))
        }
        defer {
            freeaddrinfo(result)
        }
        var addr = sockaddr_storage()
        var rp = result
        while rp != nil {
            if let ai = rp?.pointee {
                memcpy(&addr, ai.ai_addr, Int(ai.ai_addrlen))
                let result = withUnsafePointer(to: &addr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        do {
                            return try lambda($0, Int32(ai.ai_addrlen))
                        } catch {
                            print("AddrInfo.resolve: lambda threw error for address \(host):\(port): \(error)")
                            return nil
                        }
                    }
                }
                if let result {
                    return result
                }
            }
            rp = rp?.pointee.ai_next
        }
        throw Error.failedToResolve
    }
}
