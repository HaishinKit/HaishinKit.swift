import Combine
import Foundation
import HaishinKit
import libsrt

/// An actor that provides the interface to control a SRT connection.
/// Supports a one-to-one connection. Multiple connections cannot be established.
public actor SRTConnection: NetworkConnection {
    /// The error domain codes.
    public enum Error: Swift.Error {
        /// An invalid internal stare.
        case invalidState
        /// The uri isn’t supported.
        case unsupportedUri(_ uri: URL?)
        /// The fail to connect.
        case failedToConnect(_ message: String, reson: Int32)
    }

    /// The SRT Library version
    public static let version: String = SRT_VERSION_STRING
    /// The URI passed to the SRTConnection.connect() method.
    public private(set) var uri: URL?
    /// This instance connect to server(true) or not(false)
    @Published public private(set) var connected = false

    private var socket: SRTSocket? {
        didSet {
            Task {
                guard let socket else {
                    return
                }
                let networkMonitor = await socket.makeNetworkMonitor()
                self.networkMonitor = networkMonitor
                await networkMonitor.startRunning()
                for await event in await networkMonitor.event {
                    for stream in streams {
                        await stream.dispatch(event)
                    }
                }
            }
            Task {
                await oldValue?.stopRunning()
            }
        }
    }
    private var streams: [SRTStream] = []
    private var listener: SRTSocket? {
        didSet {
            Task {
                await oldValue?.stopRunning()
            }
        }
    }
    private var networkMonitor: NetworkMonitor?

    /// The SRT's performance data.
    public var performanceData: SRTPerformanceData? {
        get async {
            return await socket?.performanceData
        }
    }

    /// Creates an object.
    public init() {
        srt_startup()
    }

    deinit {
        streams.removeAll()
        srt_cleanup()
    }

    /// Open a two-way connection to an application on SRT Server.
    @available(*, deprecated, renamed: "connect")
    public func open(_ uri: URL?, mode: SRTMode = .caller) async throws {
        if uri?.absoluteString.contains("mode=") == true {
            try await connect(uri)
        } else {
            if let uri {
                if uri.absoluteString.contains("?") {
                    try await connect(URL(string: uri.absoluteString + "&mode=" + mode.rawValue))
                } else {
                    try await connect(URL(string: uri.absoluteString + "?mode=" + mode.rawValue))
                }
            } else {
                try await connect(uri)
            }
        }
    }

    /// Creates a connection to the server or waits for an incoming connection.
    ///
    /// - Parameters:
    ///   - uri: You can specify connection options in the URL. This follows the standard SRT format.
    ///
    /// - srt://192.168.1.1:9000?mode=caller
    ///   - Connect to the specified server.
    /// - srt://:9000?mode=listener
    ///   - Wait for connections as a server.
    public func connect(_ uri: URL?) async throws {
        guard let uri, let scheme = uri.scheme, let host = uri.host, let port = uri.port, scheme == "srt" else {
            throw Error.unsupportedUri(uri)
        }
        guard let mode = SRTSocketOption.getMode(uri: uri) else {
            throw Error.unsupportedUri(uri)
        }
        do {
            let options = SRTSocketOption.from(uri: uri)
            let addr = sockaddr_in(mode.host(host), port: UInt16(port))
            let socket = SRTSocket()
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Swift.Error>) in
                Task {
                    do {
                        try await socket.open(addr, mode: mode, options: options)
                        self.uri = uri
                        switch mode {
                        case .caller:
                            self.socket = socket
                        case .listener:
                            self.listener = socket
                            self.socket = try await socket.accept()
                            self.listener = nil
                        }
                        connected = await self.socket?.status == .connected
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } catch {
            throw error
        }
    }

    /// Closes a connection.
    public func close() async {
        guard uri != nil else {
            return
        }
        networkMonitor = nil
        for stream in streams {
            await stream.close()
        }
        socket = nil
        listener = nil
        uri = nil
        connected = false
    }

    func send(_ data: Data) async {
        do {
            try await socket?.send(data)
        } catch {
            await close()
        }
    }

    func recv() {
        Task {
            guard let socket else {
                return
            }
            for await data in await socket.inputs {
                await streams.first?.doInput(data)
            }
        }
    }

    func addStream(_ stream: SRTStream) {
        guard !streams.contains(where: { $0 === stream }) else {
            return
        }
        streams.append(stream)
    }

    func removeStream(_ stream: SRTStream) {
        if let index = streams.firstIndex(where: { $0 === stream }) {
            streams.remove(at: index)
        }
    }

    private func sockaddr_in(_ host: String, port: UInt16) -> sockaddr_in {
        var addr: sockaddr_in = .init()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = CFSwapInt16BigToHost(UInt16(port))
        if inet_pton(AF_INET, host, &addr.sin_addr) == 1 {
            return addr
        }
        guard let hostent = gethostbyname(host), hostent.pointee.h_addrtype == AF_INET else {
            return addr
        }
        addr.sin_addr = UnsafeRawPointer(hostent.pointee.h_addr_list[0]!).assumingMemoryBound(to: in_addr.self).pointee
        return addr
    }
}
