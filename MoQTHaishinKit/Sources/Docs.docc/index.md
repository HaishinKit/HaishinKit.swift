# ``MoQTHaishinKit``
This module supports the MoQT protocol.

@Metadata {
    @PageImage(purpose: icon, source: "moqthaishinkit-icon.svg", alt: "Media relay over QUIC")
    @PageImage(purpose: card, source: "moqthaishinkit-card.svg", alt: "Media relay over QUIC")
}

## Overview

MoQTHaishinKit implements the native QUIC client subset of
[draft-ietf-moq-transport-23](https://datatracker.ietf.org/doc/html/draft-ietf-moq-transport-23).
Connection APIs require iOS 16, macOS 13, or tvOS 16.

Connect to a `moqt://` endpoint and consume `objectStream` for incoming
subgroup objects and datagrams.

```swift
let connection = MoQTConnection(.subscriber)
let objects = await connection.objectStream
_ = try await connection.connect("moqt://relay.example/live")

do {
    let subscription = try await connection.subscribe(["live"], name: "video")
    print(subscription.trackAlias)
} catch let rejection as MoQTRequestError {
    print(rejection.code, rejection.reasonPhrase)
}

for await object in objects {
    // Use object.trackAlias to identify the subscription.
    print(object.id)
}
```

Use `publishNamespace` to advertise a namespace and `subscribeNamespace` to
receive namespace discovery updates. Both throw `MoQTRequestError` when the
peer rejects the request. For authenticated requests, supply a
`MoQTAuthorizationToken` with the token type and bytes expected by the peer.

Use `fetch(_:name:range:authorizationToken:)` to retrieve stored objects in
ascending group order. Each fetch returns its own asynchronous object stream.

Use `subscribeTracks(_:authorizationToken:)` to subscribe by namespace prefix.
The client accepts matching PUBLISH requests associated with the prefix
subscription and reports them through the returned event stream. Live objects
arrive on `objectStream` and carry the assigned track alias.

Use `setPaused(_:trackAlias:)` to change an active subscription's pause state
with REQUEST_UPDATE. The local state changes after the peer acknowledges it.
For outgoing publications, use `publish(_:name:trackAlias:authorizationToken:)`,
send subgroup objects using that alias, and call `finishPublishing(trackAlias:)`.
Incoming REQUEST_UPDATE messages can pause or resume those publications.

This client supports pause and resume updates. Other update parameters,
unsolicited incoming publications, serving incoming FETCH and SUBSCRIBE_TRACKS
requests, WebTransport, automatic session migration, and relay behavior are
outside the implemented subset.
