import Foundation

/// A value snapshot of one encoder's lifetime counters, suitable for reports and cross-actor transfer.
///
/// Durations are monotonic wall-clock seconds spent inside successful native frame-encode calls.
/// They include scheduling delays, but exclude input validation, output copying, flushing,
/// and caller-side conversion. They are not CPU utilization, power, or end-to-end latency.
/// Counters start at zero, survive invalidation, and are never reset by a settings update.
public struct AOMVideoEncoderStatistics: Codable, Sendable, Equatable {
    /// Number of frames successfully submitted to the native encoder.
    public private(set) var submittedFrameCount: UInt64 = 0
    /// Number of compressed packets returned to the caller, including packets drained by `finish()`.
    public private(set) var outputPacketCount: UInt64 = 0
    /// Total compressed payload bytes returned to the caller, excluding container/transport overhead.
    public private(set) var encodedByteCount: UInt64 = 0
    /// Native encode duration for the most recent successfully submitted frame, in seconds.
    public private(set) var lastEncodingDuration: TimeInterval = 0
    /// Sum of native encode durations for successfully submitted frames, in seconds.
    public private(set) var totalEncodingDuration: TimeInterval = 0
    /// Longest successful native frame-encode call, in seconds.
    public private(set) var maximumEncodingDuration: TimeInterval = 0
    /// Mean successful native frame-encode duration, in seconds; zero before any frames are submitted.
    public var averageEncodingDuration: TimeInterval {
        submittedFrameCount == 0 ? 0 : totalEncodingDuration / Double(submittedFrameCount)
    }

    init() { }

    mutating func recordFrame(duration: TimeInterval) {
        submittedFrameCount += 1
        lastEncodingDuration = duration
        totalEncodingDuration += duration
        maximumEncodingDuration = max(maximumEncodingDuration, duration)
    }

    mutating func recordOutput(packetCount: Int, byteCount: UInt64) {
        outputPacketCount += UInt64(packetCount)
        encodedByteCount += byteCount
    }
}
