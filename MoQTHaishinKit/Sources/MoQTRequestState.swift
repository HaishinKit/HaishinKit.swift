import Foundation

/// The latest delivery state known for an active subscription.
public struct MoQTRequestState: Sendable {
    /// Whether the subscription is paused.
    public internal(set) var isPaused: Bool
}

@available(iOS 16.0, macOS 13.0, tvOS 16.0, *)
struct MoQTActiveSubscription {
    let stream: MoQTQUICStream
    var state: MoQTRequestState
    var requestedPause: Bool?
    var pending: AsyncThrowingStream<MoQTRequestOk, any Error>.Continuation?
}
