import Foundation
import Network

/// A native QUIC client for draft-23 Media over QUIC Transport.
@available(iOS 16.0, macOS 13.0, tvOS 16.0, *)
public actor MoQTConnection {
    /// The port used when the MOQT URI omits a port.
    public static let defaultPort = 443
    /// The URI schemes accepted by this client.
    public static let supportedProtocols = ["moqt"]
    /// The default request timeout in milliseconds.
    public static let defaultRequestTimeout: UInt64 = 3000

    /// Errors reported by the connection and request handling.
    public enum Error: Swift.Error {
        /// The operation is unavailable in the current connection state.
        case invalidState
        /// The supplied URI is invalid or uses an unsupported scheme.
        case unsupportedCommand(String)
        /// The operation exceeded the configured timeout.
        case requestTimedOut
        /// The peer sent an unexpected message.
        case unknownResponse
        /// The session or stream closed before the operation completed.
        case connectionClosed
    }

    /// The application role supplied at initialization.
    public let role: MoQTSetupRole
    /// The timeout for connection setup, requests, and sends, in milliseconds.
    public let requestTimeout: UInt64
    /// The latest session-level GOAWAY notification, if one was received.
    public private(set) var goAway: MoQTGoAway?

    /// A stream of incoming subgroup and datagram objects.
    ///
    /// Reading this property again finishes the previous stream. Obtain it before subscribing.
    public var objectStream: AsyncStream<MoQTObject> {
        let (stream, continuation) = AsyncStream<MoQTObject>.makeStream()
        objectStreamContinuation?.finish()
        objectStreamContinuation = continuation
        return stream
    }

    private var socket: MoQTSocket?
    private var isReady = false
    private var setupContinuation: AsyncThrowingStream<MoQTSetup, any Swift.Error>.Continuation?
    private var outgoingControl: MoQTQUICStream?
    private var incomingControl: MoQTQUICStream?
    private typealias FetchObjects = AsyncThrowingStream<MoQTObject, any Swift.Error>
    private typealias TrackEvents = AsyncThrowingStream<MoQTTrackEvent, any Swift.Error>
    private var fetches: [UInt64: FetchObjects.Continuation] = [:]
    private var fetchRequests: [UInt64: MoQTQUICStream] = [:]
    private var fetchStreams: [UInt64: UUID] = [:]
    private var trackSubscriptions: [UInt64: TrackEvents.Continuation] = [:]
    private var trackPrefixes: [UInt64: [Data]] = [:]
    private var publications: [UInt64: MoQTActivePublication] = [:]
    private var outgoingAliases: Set<UInt64> = []
    private var subscriptions: [UInt64: MoQTActiveSubscription] = [:]
    private var nextRequestId: UInt64 = 0
    private var receivedRequestIds: Set<UInt64> = []
    private var streamTasks: [UUID: Task<Void, Never>] = [:]
    private var requestCancellations: [UUID: @Sendable () -> Void] = [:]
    private var incomingTask: Task<Void, Never>?
    private var datagramTask: Task<Void, Never>?
    private var objectStreamContinuation: AsyncStream<MoQTObject>.Continuation?

    /// Creates a MOQT client.
    ///
    /// - Parameters:
    ///   - role: The intended application role.
    ///   - requestTimeOut: The timeout in milliseconds.
    public init(_ role: MoQTSetupRole, requestTimeOut: UInt64 = MoQTConnection.defaultRequestTimeout) {
        self.role = role
        requestTimeout = requestTimeOut
    }

    /// Opens a native QUIC session and exchanges SETUP messages.
    ///
    /// - Parameter uri: The server's moqt:// URI, including any path and query.
    /// - Returns: The peer's SETUP options.
    /// - Throws: A URI, transport, timeout, or protocol error.
    public func connect(_ uri: String) async throws -> MoQTSetup {
        guard socket == nil else { throw Error.invalidState }
        guard let url = URLComponents(string: uri), url.scheme == "moqt",
              url.user == nil, url.password == nil, let authorityHost = url.percentEncodedHost,
              let host = url.host, !host.isEmpty,
              let portNumber = UInt16(exactly: url.port ?? Self.defaultPort), portNumber != 0,
              let port = NWEndpoint.Port(rawValue: portNumber) else {
            throw Error.unsupportedCommand(uri)
        }
        let authority = authorityHost + (url.port.map { ":\($0)" } ?? "")
        let path = url.percentEncodedPath + (url.percentEncodedQuery.map { "?\($0)" } ?? "")
        let socket = MoQTSocket(host: host, port: port)
        self.socket = socket
        let (setup, continuation) = AsyncThrowingStream<MoQTSetup, any Swift.Error>.makeStream()
        setupContinuation = continuation
        do {
            let message = MoQTSetup.clientMessage(authority: authority, path: path)
            guard message.body.count <= 65_535 else { throw MoQTPayload.Error.invalidField }
            let serverSetup = try await withTimeout {
                try await socket.start()
                try await self.startSession(socket, message: message)
                var iterator = setup.makeAsyncIterator()
                guard let setup = try await iterator.next() else { throw Error.connectionClosed }
                return setup
            }
            guard self.socket === socket else { throw Error.connectionClosed }
            isReady = true
            return serverSetup
        } catch {
            if self.socket === socket { close() }
            throw error
        }
    }

    /// Subscribes to a track and waits for the peer's response.
    ///
    /// - Parameters:
    ///   - namespace: The track's namespace fields.
    ///   - name: The track name within the namespace.
    ///   - authorizationToken: An optional token understood by the peer.
    /// - Returns: The accepted subscription, including its track alias.
    /// - Throws: A MoQTRequestError if the peer rejects the request, or a transport or protocol error.
    public func subscribe(_ namespace: [String], name: String,
                          authorizationToken: MoQTAuthorizationToken? = nil) async throws -> MoQTSubscribeOk {
        let (response, reader, id) = try await request(.subscribe, namespace: namespace, name: name,
                                                       authorizationToken: authorizationToken, keepOpen: true)
        do {
            guard response.type == MoQTMessageType.subscribeOK.rawValue else { throw Error.unknownResponse }
            var body = MoQTPayload(response.body)
            let ok = try MoQTSubscribeOk(&body)
            guard subscriptions[ok.trackAlias] == nil else { throw Error.unknownResponse }
            subscriptions[ok.trackAlias] = .init(stream: reader.stream, state: .init(isPaused: false))
            streamTasks[id] = Task { await drainRequest(reader, id: id, trackAlias: ok.trackAlias) }
            return ok
        } catch {
            finishStream(id)
            close()
            throw error
        }
    }

    /// Queries the status of a track without opening a subscription.
    ///
    /// - Parameters:
    ///   - namespace: The track's namespace fields.
    ///   - name: The track name within the namespace.
    ///   - authorizationToken: An optional token understood by the peer.
    /// - Returns: The track's latest known location and properties, if reported.
    /// - Throws: A `MoQTRequestError` for a peer rejection, or a transport or protocol error.
    public func trackStatus(_ namespace: [String], name: String,
                            authorizationToken: MoQTAuthorizationToken? = nil) async throws -> MoQTRequestOk {
        let (response, _, _) = try await request(.trackStatus, namespace: namespace, name: name,
                                                 authorizationToken: authorizationToken)
        do {
            guard response.type == MoQTMessageType.requestOK.rawValue else { throw Error.unknownResponse }
            var body = MoQTPayload(response.body)
            return try MoQTRequestOk(&body, includesTrackInformation: true)
        } catch {
            close()
            throw error
        }
    }

    /// Advertises a namespace to the peer.
    ///
    /// - Parameters:
    ///   - namespace: The namespace prefix to advertise.
    ///   - authorizationToken: An optional token understood by the peer.
    /// - Returns: The peer's acknowledgement.
    /// - Throws: A MoQTRequestError if the peer rejects the request, or a transport or protocol error.
    public func publishNamespace(_ namespace: [String],
                                 authorizationToken: MoQTAuthorizationToken? = nil) async throws -> MoQTRequestOk {
        let (ok, reader, id) = try await namespaceRequest(.publishNamespace, namespace, authorizationToken)
        streamTasks[id] = Task { await drainRequest(reader, id: id) }
        return ok
    }

    /// Subscribes to namespace discovery under a prefix.
    ///
    /// - Parameters:
    ///   - namespace: The prefix to match. Pass an empty array to match all namespaces.
    ///   - authorizationToken: An optional token understood by the peer.
    /// - Returns: The peer's acknowledgement and a stream of discovery events.
    /// - Throws: A MoQTRequestError if the peer rejects the request, or a transport or protocol error.
    public func subscribeNamespace(_ namespace: [String], authorizationToken: MoQTAuthorizationToken? = nil)
        async throws -> (response: MoQTRequestOk, updates: AsyncThrowingStream<MoQTNamespaceUpdate, any Swift.Error>) {
        let (ok, reader, id) = try await namespaceRequest(.subscribeNamespace, namespace, authorizationToken)
        let (updates, continuation) = AsyncThrowingStream<MoQTNamespaceUpdate, any Swift.Error>.makeStream()
        continuation.onTermination = { [weak self] _ in
            Task { await self?.finishStream(id) }
        }
        streamTasks[id] = Task { await drainRequest(reader, id: id, updates: continuation) }
        return (ok, updates)
    }

    /// Fetches stored objects in ascending group order.
    ///
    /// - Parameters:
    ///   - namespace: The track namespace.
    ///   - name: The track name.
    ///   - range: An inclusive location range. Pass nil to request all available objects.
    ///   - authorizationToken: A token understood by the peer.
    /// - Returns: The peer response and the fetched objects. Cancelling iteration cancels the fetch.
    /// - Throws: A peer rejection, transport error, or protocol error.
    public func fetch(_ namespace: [String], name: String, range: MoQTFetchRange? = nil, authorizationToken: MoQTAuthorizationToken? = nil)
        async throws -> (response: MoQTRequestOk, objects: AsyncThrowingStream<MoQTObject, any Swift.Error>) {
        let (objects, continuation) = FetchObjects.makeStream()
        let session = socket
        let requestId = nextRequestId
        guard isReady else { throw Error.invalidState }
        do {
            let (response, reader, id) = try await request(.fetch, namespace: namespace, name: name,
                                                           authorizationToken: authorizationToken, keepOpen: true, fetchRange: range) { connection, id in
                connection.fetches[id] = continuation
                continuation.onTermination = { [weak self] termination in
                    if case .cancelled = termination {
                        Task { await self?.cancelFetch(id, socket: session) }
                    }
                }
            }
            guard response.type == MoQTMessageType.requestOK.rawValue else {
                throw Error.unknownResponse
            }
            var body = MoQTPayload(response.body)
            let ok = try MoQTRequestOk(&body, includesTrackInformation: true)
            if fetches[requestId] != nil {
                fetchRequests[requestId] = reader.stream
            } else {
                try await reader.stream.send(Data(), endOfStream: true)
            }
            streamTasks[id] = Task { await drainRequest(reader, id: id) }
            return (ok, objects)
        } catch {
            cancelFetch(requestId, socket: session)
            throw error
        }
    }

    /// Subscribes to tracks matching a namespace prefix and accepts publications associated with that request.
    ///
    /// Pass an empty prefix to match all namespaces. The returned event stream reports accepted
    /// publications and skipped tracks. Incoming objects are delivered through `objectStream`.
    ///
    /// - Parameters:
    ///   - namespace: The namespace prefix to match.
    ///   - authorizationToken: A token understood by the peer.
    /// - Throws: A peer rejection, transport error, or protocol error.
    public func subscribeTracks(_ namespace: [String], authorizationToken: MoQTAuthorizationToken? = nil)
        async throws -> (response: MoQTRequestOk, events: AsyncThrowingStream<MoQTTrackEvent, any Swift.Error>) {
        let (events, continuation) = TrackEvents.makeStream()
        let session = socket
        let requestId = nextRequestId
        do {
            let (response, reader, id) = try await request(.subscribeTracks, namespace: namespace,
                                                           authorizationToken: authorizationToken, keepOpen: true) { connection, id in
                connection.trackSubscriptions[id] = continuation
                connection.trackPrefixes[id] = namespace.map { Data($0.utf8) }
            }
            guard response.type == MoQTMessageType.requestOK.rawValue else {
                throw Error.unknownResponse
            }
            var body = MoQTPayload(response.body)
            let ok = try MoQTRequestOk(&body)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.finishStream(id) }
            }
            streamTasks[id] = Task {
                await drainRequest(reader, id: id, trackEvents: continuation)
                if self.socket === session {
                    trackSubscriptions.removeValue(forKey: requestId)
                    trackPrefixes.removeValue(forKey: requestId)
                }
            }
            return (ok, events)
        } catch {
            if self.socket === session {
                trackSubscriptions.removeValue(forKey: requestId)
                trackPrefixes.removeValue(forKey: requestId)
            }
            continuation.finish(throwing: error)
            throw error
        }
    }

    /// Returns the latest pause state for a track alias, if the subscription is active.
    public func subscriptionState(trackAlias: UInt64) -> MoQTRequestState? {
        subscriptions[trackAlias]?.state
    }

    /// Changes the pause state of an active subscription using REQUEST_UPDATE.
    ///
    /// Only one update can be outstanding per track. The state changes after the peer acknowledges
    /// the update. A rejected update throws `MoQTRequestError`.
    public func setPaused(_ paused: Bool, trackAlias: UInt64) async throws -> MoQTRequestOk {
        guard let subscription = subscriptions[trackAlias], subscription.pending == nil,
              nextRequestId <= UInt64.max - 2 else { throw Error.invalidState }
        let (responses, continuation) = AsyncThrowingStream<MoQTRequestOk, any Swift.Error>.makeStream()
        subscriptions[trackAlias]?.requestedPause = paused
        subscriptions[trackAlias]?.pending = continuation
        var body = MoQTPayload()
        body.putInt(nextRequestId)
        nextRequestId += 2
        body.putInt(1)
        body.putInt(0x11)
        body.putByte(paused ? 1 : 0)
        let message = MoQTControlMessage(.requestUpdate, body.data)
        defer {
            if subscriptions[trackAlias]?.stream === subscription.stream {
                subscriptions[trackAlias]?.pending = nil
                subscriptions[trackAlias]?.requestedPause = nil
            }
        }
        do {
            return try await withTimeout {
                try await subscription.stream.send(message.data)
                var iterator = responses.makeAsyncIterator()
                guard let result = try await iterator.next() else { throw CancellationError() }
                return result
            }
        } catch {
            if !(error is MoQTRequestError) { subscription.stream.cancel() }
            throw error
        }
    }

    private func cancelFetch(_ requestId: UInt64, socket: MoQTSocket?) {
        guard self.socket === socket else { return }
        fetches.removeValue(forKey: requestId)?.finish(throwing: CancellationError())
        if let id = fetchStreams.removeValue(forKey: requestId) { finishStream(id) }
        fetchRequests.removeValue(forKey: requestId)?.cancel()
    }

    private func receiveFetch(_ reader: inout MoQTStreamReader, id: UUID) async throws {
        guard let requestId = try await reader.read({ try $0.getInt() }),
              let continuation = fetches[requestId] else {
            reader.stream.cancel()
            return
        }
        guard fetchStreams[requestId] == nil else { throw Error.unknownResponse }
        let session = socket
        fetchStreams[requestId] = id
        defer {
            if self.socket === session {
                fetchStreams.removeValue(forKey: requestId)
                fetches.removeValue(forKey: requestId)
                if let request = fetchRequests.removeValue(forKey: requestId) {
                    Task { try? await request.send(Data(), endOfStream: true) }
                }
            }
        }
        do {
            var decoder = MoQTFetchDecoder()
            while let entry = try await reader.read({ try decoder.decode(&$0) }) {
                if let object = entry { continuation.yield(object) }
            }
            continuation.finish()
        } catch {
            continuation.finish(throwing: error)
            throw error
        }
    }

    private func acceptPublication(reader: inout MoQTStreamReader, id: UUID, socket: MoQTSocket) async throws {
        guard let publication = try await reader.read({ payload in
            var body = MoQTPayload(try payload.getBytes(limit: 65_535))
            return try MoQTPublish(&body)
        }), self.socket === socket, !publication.requestId.isMultiple(of: 2),
              receivedRequestIds.insert(publication.requestId).inserted else { throw MoQTPayload.Error.invalidField }

        let parentId = try publication.parameters.fields.first(where: { $0.type == 0x36 }).map { field in
            var payload = MoQTPayload(field.value)
            return try payload.getInt()
        }
        guard let parentId, let events = trackSubscriptions[parentId], let prefix = trackPrefixes[parentId],
              publication.namespace.starts(with: prefix) else {
            var body = MoQTPayload()
            body.putInt(0x20) // UNINTERESTED
            body.putInt(0)
            body.putBytes(Data())
            try await reader.stream.send(MoQTControlMessage(.requestError, body.data).data, endOfStream: true)
            return
        }
        let alias = publication.trackAlias
        guard subscriptions[alias] == nil else { throw Error.unknownResponse }
        let paused = publication.parameters.fields.first(where: { $0.type == 0x11 })?.value.first == 1
        subscriptions[alias] = .init(stream: reader.stream, state: .init(isPaused: paused))
        do {
            try await reader.stream.send(MoQTControlMessage(.requestOK, Data([0])).data)
        } catch {
            if subscriptions[alias]?.stream === reader.stream { subscriptions.removeValue(forKey: alias) }
            throw error
        }
        events.yield(.published(.init(namespace: publication.namespace, name: publication.name,
                                      trackAlias: alias, properties: publication.trackProperties)))
        await drainRequest(reader, id: id, trackAlias: alias)
    }

    /// Offers a track to the peer and waits for acceptance before sending objects.
    ///
    /// Use the same track alias in subgroup headers and call `finishPublishing(trackAlias:)`
    /// after sending the last subgroup. The peer can pause delivery using REQUEST_UPDATE.
    ///
    /// - Parameters:
    ///   - namespace: The track namespace.
    ///   - name: The track name.
    ///   - trackAlias: An alias that has not been used for a publication in this session.
    ///   - authorizationToken: A token understood by the peer.
    /// - Throws: A peer rejection, transport error, or protocol error.
    public func publish(_ namespace: [String], name: String, trackAlias: UInt64,
                        authorizationToken: MoQTAuthorizationToken? = nil) async throws -> MoQTRequestOk {
        guard outgoingAliases.insert(trackAlias).inserted else { throw Error.invalidState }
        let session = socket
        do {
            let (response, reader, id) = try await request(.publish, namespace: namespace, name: name,
                                                           authorizationToken: authorizationToken, keepOpen: true,
                                                           publicationAlias: trackAlias)
            guard response.type == MoQTMessageType.requestOK.rawValue else { throw Error.unknownResponse }
            var body = MoQTPayload(response.body)
            let ok = try MoQTRequestOk(&body)
            publications[trackAlias] = .init(stream: reader.stream)
            streamTasks[id] = Task { await runPublication(reader, id: id, alias: trackAlias) }
            return ok
        } catch {
            if self.socket === session { outgoingAliases.remove(trackAlias) }
            throw error
        }
    }

    /// Reports whether the peer has paused delivery of an outgoing publication.
    public func publicationIsPaused(trackAlias: UInt64) -> Bool? {
        publications[trackAlias]?.isPaused
    }

    /// Sends PUBLISH_DONE with TRACK_ENDED and finishes the publication's response direction.
    ///
    /// Wait for all subgroup sends to finish before calling this method.
    public func finishPublishing(trackAlias: UInt64) async throws {
        guard var publication = publications[trackAlias], !publication.finished,
              publication.inFlight == 0 else { throw Error.invalidState }
        publication.finished = true
        publications[trackAlias] = publication
        var body = MoQTPayload()
        body.putInt(2) // TRACK_ENDED
        body.putInt(publication.streamCount)
        body.putBytes(Data())
        let message = MoQTControlMessage(.publishDone, body.data)
        let stream = publication.stream
        do {
            try await withTimeout {
                try await stream.send(message.data, endOfStream: true)
            }
        } catch {
            publication.stream.cancel()
            throw error
        }
    }

    private func runPublication(_ initialReader: MoQTStreamReader, id: UUID, alias: UInt64) async {
        var reader = initialReader
        defer {
            if publications[alias]?.stream === reader.stream { publications.removeValue(forKey: alias) }
            finishStream(id)
        }
        do {
            while let message = try await reader.read(MoQTControlMessage.init) {
                guard message.type == MoQTMessageType.requestUpdate.rawValue,
                      publications[alias]?.stream === reader.stream else { throw Error.unknownResponse }
                var body = MoQTPayload(message.body)
                let update = try MoQTRequestUpdate(&body)
                guard !update.requestId.isMultiple(of: 2), receivedRequestIds.insert(update.requestId).inserted else {
                    throw MoQTPayload.Error.invalidField
                }
                guard update.parameters.fields.allSatisfy({ $0.type == 0x11 }) else {
                    var rejection = MoQTPayload()
                    rejection.putInt(3) // NOT_SUPPORTED
                    rejection.putInt(0)
                    rejection.putBytes(Data())
                    try await reader.stream.send(MoQTControlMessage(.requestError, rejection.data).data)
                    continue
                }
                if let paused = update.parameters.fields.first?.value.first {
                    publications[alias]?.isPaused = paused == 1
                }
                try await reader.stream.send(MoQTControlMessage(.requestOK, Data([0])).data)
            }
        } catch {
            reader.stream.cancel()
        }
    }

    /// Sends a subgroup on a new unidirectional stream and finishes that stream.
    ///
    /// - Parameters:
    ///   - objects: The subgroup's objects in strictly increasing object ID order.
    ///   - header: The track alias, group, subgroup, and priority for the stream.
    /// - Throws: An encoding, transport, or timeout error.
    public func send(_ objects: [MoQTObject], header: MoQTStreamHeaderSubgroup) async throws {
        guard isReady, let socket else { throw Error.invalidState }
        var payload = MoQTPayload(header.payload)
        var previous: UInt64?
        for object in objects {
            try object.encode(after: previous, into: &payload)
            previous = object.id
        }
        let alias = header.trackAlias
        if let publication = publications[alias] {
            guard !publication.isPaused, !publication.finished else { throw Error.invalidState }
            publications[alias]?.inFlight += 1
        } else if outgoingAliases.contains(alias) {
            throw Error.invalidState
        }
        let publicationStream = publications[alias]?.stream
        defer {
            if let publicationStream, publications[alias]?.stream === publicationStream {
                publications[alias]?.inFlight -= 1
            }
        }
        let data = payload.data
        try await withTimeout {
            let stream = try await socket.openStream(.unidirectional)
            try await stream.send(data, endOfStream: true)
        }
        if let publicationStream, publications[alias]?.stream === publicationStream {
            publications[alias]?.streamCount += 1
        }
    }

    /// Closes the session, cancels pending requests, and finishes the object stream.
    public func close() {
        isReady = false
        goAway = nil
        nextRequestId = 0
        receivedRequestIds.removeAll()
        for continuation in fetches.values { continuation.finish(throwing: Error.connectionClosed) }
        fetches.removeAll()
        fetchStreams.removeAll()
        for stream in fetchRequests.values { stream.cancel() }
        fetchRequests.removeAll()
        for continuation in trackSubscriptions.values { continuation.finish(throwing: Error.connectionClosed) }
        trackSubscriptions.removeAll()
        trackPrefixes.removeAll()
        for subscription in subscriptions.values {
            subscription.pending?.finish(throwing: Error.connectionClosed)
            subscription.stream.cancel()
        }
        subscriptions.removeAll()
        for publication in publications.values { publication.stream.cancel() }
        publications.removeAll()
        outgoingAliases.removeAll()
        if let socket { Task { await socket.close() } }
        socket = nil
        setupContinuation?.finish(throwing: Error.connectionClosed)
        setupContinuation = nil
        outgoingControl = nil
        incomingControl = nil
        incomingTask?.cancel()
        incomingTask = nil
        datagramTask?.cancel()
        datagramTask = nil
        for task in streamTasks.values { task.cancel() }
        streamTasks.removeAll()
        for cancel in requestCancellations.values { cancel() }
        requestCancellations.removeAll()
        objectStreamContinuation?.finish()
        objectStreamContinuation = nil
    }

    private func startSession(_ socket: MoQTSocket, message: MoQTControlMessage) async throws {
        guard self.socket === socket else { throw Error.connectionClosed }
        incomingTask = Task { [weak self] in
            await socket.receiveStreams { [weak self] stream in
                await self?.acceptStream(stream, socket: socket)
            }
            await self?.sessionEnded(socket, error: Error.connectionClosed)
        }
        datagramTask = Task { [weak self] in
            await socket.receiveDatagrams { [weak self] datagram in
                await self?.receiveDatagram(datagram, socket: socket)
            }
        }
        let control = try await socket.openStream(.unidirectional)
        guard self.socket === socket else { throw Error.connectionClosed }
        outgoingControl = control
        try await control.send(message.data)
    }

    private func sessionEnded(_ socket: MoQTSocket, error: any Swift.Error) {
        guard self.socket === socket else { return }
        setupContinuation?.finish(throwing: error)
        close()
    }

    private func acceptStream(_ stream: MoQTQUICStream, socket: MoQTSocket) {
        guard self.socket === socket else { return }
        let id = UUID()
        streamTasks[id] = Task { await receiveStream(stream, id: id, socket: socket) }
    }

    private func receiveDatagram(_ data: Data, socket: MoQTSocket) {
        guard self.socket === socket, isReady else { return }
        do {
            var payload = MoQTPayload(data)
            if let object = try MoQTObject.readDatagram(&payload) { objectStreamContinuation?.yield(object) }
        } catch {
            close()
        }
    }

    private func request(_ type: MoQTMessageType, namespace: [String], name: String? = nil,
                         authorizationToken: MoQTAuthorizationToken?, keepOpen: Bool = false, publicationAlias: UInt64? = nil, fetchRange: MoQTFetchRange? = nil,
                         prepare: (isolated MoQTConnection, UInt64) -> Void = { _, _ in }) async throws -> (MoQTControlMessage, MoQTStreamReader, UUID) {
        guard isReady, goAway == nil, let socket, nextRequestId <= UInt64.max - 2 else {
            throw Error.invalidState
        }
        var body = MoQTPayload()
        body.putInt(nextRequestId)
        try body.putNamespace(namespace)
        if let name {
            guard namespace.reduce(name.utf8.count, { $0 + $1.utf8.count }) <= 4096 else {
                throw MoQTPayload.Error.invalidField
            }
            body.putBytes(Data(name.utf8))
        }
        if let publicationAlias { body.putInt(publicationAlias) }
        let tokenCount: UInt64 = authorizationToken == nil ? 0 : 1
        let parameterCount: UInt64 = type == .subscribe ? 3 : (type == .fetch ? 1 : 0)
        body.putInt(tokenCount + parameterCount + (fetchRange == nil ? 0 : 1))
        authorizationToken?.encodeParameter(in: &body)
        if type == .subscribe {
            body.putInt(0x20 - (tokenCount == 0 ? 0 : 3)) // SUBSCRIBER_PRIORITY
            body.putByte(0)
            body.putInt(1) // LOCATION_FILTER
            body.putInt(1) // Relative Start
            body.putInt(1) // Current group
            body.putInt(1) // GROUP_ORDER
            body.putByte(2) // Descending
        } else if type == .fetch {
            if let fetchRange {
                body.putInt(0x21 - (tokenCount == 0 ? 0 : 3))
                try fetchRange.encode(into: &body)
                body.putInt(1) // GROUP_ORDER follows LOCATION_FILTER.
            } else {
                body.putInt(0x22 - (tokenCount == 0 ? 0 : 3))
            }
            body.putByte(1) // Ascending
        }
        guard body.data.count <= 65_535 else { throw MoQTPayload.Error.invalidField }
        let data = MoQTControlMessage(type, body.data).data
        let id = UUID()
        prepare(self, nextRequestId)
        nextRequestId += 2
        let pending = Task {
            try await withTimeout {
                let stream = try await socket.openStream(.bidirectional)
                try await stream.send(data, endOfStream: !keepOpen)
                var reader = MoQTStreamReader(stream)
                guard let message = try await reader.read(MoQTControlMessage.init) else { throw Error.connectionClosed }
                return (message, reader)
            }
        }
        requestCancellations[id] = { pending.cancel() }
        defer { requestCancellations[id] = nil }
        let (response, reader) = try await withTaskCancellationHandler {
            try await pending.value
        } onCancel: {
            pending.cancel()
        }
        try Task.checkCancellation()
        guard self.socket === socket else { throw Error.connectionClosed }
        if response.type == MoQTMessageType.requestError.rawValue {
            var body = MoQTPayload(response.body)
            let rejection: MoQTRequestError
            do {
                rejection = try MoQTRequestError(&body)
            } catch {
                close()
                throw error
            }
            throw rejection
        }
        return (response, reader, id)
    }

    private func namespaceRequest(_ type: MoQTMessageType, _ namespace: [String], _ token: MoQTAuthorizationToken?)
        async throws -> (MoQTRequestOk, MoQTStreamReader, UUID) {
        let (response, reader, id) = try await request(type, namespace: namespace, authorizationToken: token)
        do {
            guard response.type == MoQTMessageType.requestOK.rawValue else { throw Error.unknownResponse }
            var body = MoQTPayload(response.body)
            return (try MoQTRequestOk(&body), reader, id)
        } catch {
            finishStream(id)
            close()
            throw error
        }
    }

    private func receiveStream(_ stream: MoQTQUICStream, id: UUID, socket: MoQTSocket) async {
        defer { finishStream(id) }
        var reader = MoQTStreamReader(stream)
        do {
            guard let type = try await reader.read({ try $0.getInt() }) else { return }
            guard self.socket === socket else { return }
            if stream.isBidirectional {
                if type == MoQTMessageType.publish.rawValue {
                    try await acceptPublication(reader: &reader, id: id, socket: socket)
                } else {
                    try await rejectIncomingRequest(type, reader: &reader, socket: socket)
                }
                return
            }
            switch type {
            case MoQTMessageType.setup.rawValue:
                guard incomingControl == nil, let continuation = setupContinuation else { throw Error.unknownResponse }
                incomingControl = stream
                guard let setup = try await reader.read({ payload in
                    var body = MoQTPayload(try payload.getBytes(limit: 65_535))
                    return try MoQTSetup(&body)
                }) else { throw Error.connectionClosed }
                continuation.yield(setup)
                continuation.finish()
                setupContinuation = nil
                while let message = try await reader.read(MoQTControlMessage.init) {
                    guard self.socket === socket else { return }
                    guard message.type == MoQTMessageType.goaway.rawValue, goAway == nil else {
                        throw Error.unknownResponse
                    }
                    var body = MoQTPayload(message.body)
                    goAway = try MoQTGoAway(&body)
                }
                if self.socket === socket { close() }
            case 0x132b3e28:
                break
            case 5:
                try await receiveFetch(&reader, id: id)
            case 0..<128 where type & 0x10 != 0:
                guard isReady, let header = try await reader.read({ try MoQTStreamHeaderSubgroup(flags: type, payload: &$0) }) else {
                    return
                }
                var previous: UInt64?
                var subgroupId = header.subgroupId
                while let object = try await reader.read({ try MoQTObject.readSubgroup(&$0, header: header, previous: previous, subgroupId: subgroupId) }) {
                    guard self.socket === socket else { return }
                    objectStreamContinuation?.yield(object)
                    previous = object.id
                    subgroupId = object.subgroupId
                }
            default:
                throw Error.unknownResponse
            }
        } catch {
            if self.socket === socket, incomingControl === stream || !(error is NWError) {
                setupContinuation?.finish(throwing: error)
                close()
            }
        }
    }

    private func rejectIncomingRequest(_ type: UInt64, reader: inout MoQTStreamReader, socket: MoQTSocket) async throws {
        guard let messageType = MoQTMessageType(rawValue: type) else { throw Error.unknownResponse }
        guard let requestId = try await reader.read({ payload in
            var body = MoQTPayload(try payload.getBytes(limit: 65_535))
            switch messageType {
            case .publish: return try MoQTPublish(&body).requestId
            case .fetch: return try MoQTFetch(&body).requestId
            case .trackStatus: return try MoQTTrackStatus(&body).requestId
            case .subscribeTracks: return try MoQTSubscribeTracks(&body).requestId
            case .subscribe, .publishNamespace, .subscribeNamespace: return try body.getInt()
            default: throw Error.unknownResponse
            }
        }), self.socket === socket, !requestId.isMultiple(of: 2),
              receivedRequestIds.insert(requestId).inserted else { throw MoQTPayload.Error.invalidField }
        var body = MoQTPayload()
        body.putInt(3) // NOT_SUPPORTED
        body.putInt(0)
        body.putBytes(Data())
        try await reader.stream.send(MoQTControlMessage(.requestError, body.data).data, endOfStream: true)
    }

    private func drainRequest(_ initialReader: MoQTStreamReader, id: UUID,
                              updates: AsyncThrowingStream<MoQTNamespaceUpdate, any Swift.Error>.Continuation? = nil,
                              trackAlias: UInt64? = nil,
                              trackEvents: TrackEvents.Continuation? = nil) async {
        var reader = initialReader
        var receivedGoAway = false
        var namespaces: Set<[Data]> = []
        defer {
            finishStream(id)
            if let trackAlias, subscriptions[trackAlias]?.stream === reader.stream {
                subscriptions.removeValue(forKey: trackAlias)?.pending?.finish(throwing: Error.connectionClosed)
            }
        }
        do {
            while let message = try await reader.read(MoQTControlMessage.init) {
                var body = MoQTPayload(message.body)
                switch MoQTMessageType(rawValue: message.type) {
                case .namespace where updates != nil:
                    let suffix = try body.getNamespace()
                    try decodeNamespaceParameters(&body)
                    namespaces.insert(suffix)
                    updates?.yield(.available(suffix))
                case .namespaceDone where updates != nil:
                    let suffix = try body.getNamespace()
                    guard body.bytesAvailable == 0, namespaces.remove(suffix) != nil else {
                        throw MoQTPayload.Error.invalidField
                    }
                    updates?.yield(.unavailable(suffix))
                case .publishSkipped where trackEvents != nil:
                    let skipped = try MoQTPublishSkipped(&body)
                    trackEvents?.yield(.skipped(namespaceSuffix: skipped.namespaceSuffix, name: skipped.name))
                case .publishDone where trackAlias != nil:
                    _ = try MoQTPublishDone(&body)
                    if let trackAlias, subscriptions[trackAlias]?.stream === reader.stream {
                        subscriptions.removeValue(forKey: trackAlias)?.pending?.finish(throwing: Error.connectionClosed)
                    }
                    try await reader.stream.send(Data(), endOfStream: true)
                    return
                case .publishStateNotify where updates == nil:
                    let state = try MoQTPublishStateNotify(&body)
                    if let trackAlias, subscriptions[trackAlias]?.stream === reader.stream,
                       let paused = state.parameters.fields.first(where: { $0.type == 0x11 })?.value.first {
                        subscriptions[trackAlias]?.state.isPaused = paused == 1
                    }
                case .requestOK, .requestError:
                    guard let trackAlias, subscriptions[trackAlias]?.stream === reader.stream,
                          let pending = subscriptions[trackAlias]?.pending,
                          let paused = subscriptions[trackAlias]?.requestedPause else { throw Error.unknownResponse }
                    subscriptions[trackAlias]?.requestedPause = nil
                    if message.type == MoQTMessageType.requestOK.rawValue {
                        let response = try MoQTRequestOk(&body, allowsLargestObject: true)
                        subscriptions[trackAlias]?.state.isPaused = paused
                        pending.yield(response)
                        pending.finish()
                    } else {
                        pending.finish(throwing: try MoQTRequestError(&body))
                    }
                case .goaway:
                    guard !receivedGoAway else { throw Error.unknownResponse }
                    _ = try MoQTGoAway(&body)
                    receivedGoAway = true
                default:
                    throw Error.unknownResponse
                }
            }
            updates?.finish()
            trackEvents?.finish()
        } catch {
            updates?.finish(throwing: error)
            trackEvents?.finish(throwing: error)
        }
    }

    private func decodeNamespaceParameters(_ body: inout MoQTPayload) throws {
        let count = try body.getInt()
        var type: UInt64 = 0
        for _ in 0..<count {
            let (next, overflow) = type.addingReportingOverflow(try body.getInt())
            guard !overflow, next == 3 else { throw MoQTPayload.Error.invalidField }
            type = next
            _ = try body.getBytes() // AUTHORIZATION_TOKEN
        }
        guard body.bytesAvailable == 0 else { throw MoQTPayload.Error.invalidField }
    }

    private func finishStream(_ id: UUID) {
        streamTasks.removeValue(forKey: id)?.cancel()
    }

    private func withTimeout<Value: Sendable>(_ operation: @escaping @Sendable () async throws -> Value) async throws -> Value {
        let timeout = requestTimeout
        return try await withThrowingTaskGroup(of: Value.self) { group in
            group.addTask(operation: operation)
            group.addTask {
                try await Task.sleep(for: .milliseconds(timeout))
                throw Error.requestTimedOut
            }
            defer { group.cancelAll() }
            guard let value = try await group.next() else { throw CancellationError() }
            return value
        }
    }
}
