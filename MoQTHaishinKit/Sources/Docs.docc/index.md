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

This client supports outgoing track subscriptions, track status queries, and namespace requests.
Incoming track requests are rejected with `NOT_SUPPORTED`. The subgroup
sending API writes objects to a unidirectional QUIC stream using a
caller-supplied track alias. WebTransport, FETCH, request updates, automatic
session migration, and relay behavior are outside the implemented subset.

The wire codecs also cover FETCH, PUBLISH, PUBLISH_DONE, PUBLISH_STATE_NOTIFY,
PUBLISH_SKIPPED, REQUEST_UPDATE, and SUBSCRIBE_TRACKS. Session APIs currently
expose track status queries and the existing subscription and namespace operations.
