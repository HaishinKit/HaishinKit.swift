@available(iOS 16.0, macOS 13.0, tvOS 16.0, *)
struct MoQTActivePublication {
    let stream: MoQTQUICStream
    var isPaused = false
    var streamCount: UInt64 = 0
    var inFlight = 0
    var finished = false
}
