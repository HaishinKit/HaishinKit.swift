import Combine
import Foundation
import HaishinKit
import libsrt

/// Manages an SRT connection for publishing or receiving media.
///
/// Each instance supports one peer connection at a time.
public actor SRTConnection: NetworkConnection {
    /// Errors that can occur when connecting or configuring an SRT connection.
    public enum Error: Swift.Error {
        /// The operation is invalid in the current state, or connection setup failed without a rejection reason.
        case invalidState
        /// The endpoint URL is missing or does not use the `srt` scheme.
        case unsupportedUri(_ uri: URL?)
        /// Connection setup failed with the associated SRT rejection reason.
        case failedToConnect(_ reason: SRTRejectReason)
    }

    /// The version of the underlying SRT library.
    public static let version: String = SRT_VERSION_STRING
    /// The endpoint URL recorded during connection setup, or `nil` after closing.
    public private(set) var uri: URL?
    /// A Boolean value that indicates whether the SRT connection is established.
    @Published public private(set) var connected = false
    /// The latest socket statistics, or `nil` if no socket exists.
    ///
    /// Reading this property returns the cached snapshot; it does not request a new measurement.
    public var performanceData: SRTPerformanceData? {
        get async {
            return await socket?.performanceData
        }
    }

    private var socket: SRTSocket?
    private var streams: [SRTStream] = []
    private var listener: SRTSocket?
    private var networkMonitor: NetworkMonitor?

    /// Creates a connection and initializes the SRT library.
    public init() {
        srt_startup()
        socket = SRTSocket()
    }

    deinit {
        streams.removeAll()
        srt_cleanup()
    }

    /// Reads an option from the current socket.
    ///
    /// - Parameter name: The option to read.
    /// - Returns: The option value, or `nil` if no socket exists.
    /// - Throws: `SRTSocketOption.Error.invalidOption` if the library cannot read the option.
    public func getSocketOption(_ name: SRTSocketOption.Name) async throws -> SRTSocketOption? {
        try await socket?.getSocketOption(name)
    }

    /// Applies an option to the current socket.
    ///
    /// Before connecting, this method accepts only `.pre` options. After connecting,
    /// it accepts only `.post` options. Supply options that require `.preBind` through
    /// the connection URL.
    ///
    /// - Parameter option: The option and value to apply.
    /// - Throws: `Error.invalidState` if the option is not allowed in the current state,
    ///   or `SRTSocketOption.Error.invalidOption` if the library rejects the option.
    public func setSocketOption(_ option: SRTSocketOption) async throws {
        if connected {
            guard option.name.restriction == .post else {
                throw Error.invalidState
            }
            try await socket?.setSocketOption(option)
        } else {
            guard option.name.restriction == .pre else {
                throw Error.invalidState
            }
            try await socket?.setSocketOption(option)
        }
    }

    /// Connects to a peer or waits for an incoming connection.
    ///
    /// Specify the mode and socket options as URL query parameters:
    /// - `srt://192.168.1.1:9000?mode=caller` connects to the specified peer.
    /// - `srt://:9000?mode=listener` waits for a peer on the specified port.
    ///
    /// - Parameter uri: The SRT endpoint URL.
    /// - Throws: `Error.unsupportedUri` for an invalid URL, `Error.failedToConnect`
    ///   for an SRT rejection, or `Error.invalidState` for other setup failures.
    public func connect(_ uri: URL?) async throws {
        guard let url = SRTSocketURL(uri) else {
            throw Error.unsupportedUri(uri)
        }
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Swift.Error>) in
                Task {
                    do {
                        try await socket?.open(url)
                        self.uri = uri
                        switch url.mode {
                        case .caller:
                            break
                        case .listener:
                            listener = socket
                            socket = try await listener?.accept(url.options)
                            await listener?.stopRunning()
                            listener = nil
                        case .rendezvous:
                            break
                        }
                        connected = await socket?.status == .connected
                        continuation.resume()
                    } catch {
                        socket = SRTSocket()
                        continuation.resume(throwing: error)
                    }
                }
            }
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
        } catch let error as SRTSocket.Error {
            switch error {
            case .rejected(let reason):
                throw Error.failedToConnect(reason)
            default:
                throw Error.invalidState
            }
        } catch {
            throw Error.invalidState
        }
    }

    /// Closes the connection and its streams, stops network monitoring, and resets the socket.
    public func close() async {
        guard uri != nil else {
            return
        }
        await networkMonitor?.stopRunning()
        networkMonitor = nil
        for stream in streams {
            await stream.close()
        }
        await socket?.stopRunning()
        socket = nil
        await listener?.stopRunning()
        listener = nil
        uri = nil
        connected = false
        socket = SRTSocket()
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
            await close()
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
}
