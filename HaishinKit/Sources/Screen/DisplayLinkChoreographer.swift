import Foundation

#if os(macOS)
import CoreVideo

// swiftlint:disable attributes
// CADisplayLink is deprecated, I've given up on making it conform to Sendable.
final class DisplayLink: NSObject, @unchecked Sendable {
    private static let preferredFramesPerSecond = 0

    var isPaused = false {
        didSet {
            guard let displayLink, oldValue != isPaused else {
                return
            }
            if isPaused {
                CVDisplayLinkStop(displayLink)
            } else {
                CVDisplayLinkStart(displayLink)
            }
        }
    }
    var preferredFramesPerSecond = DisplayLink.preferredFramesPerSecond {
        didSet {
            guard preferredFramesPerSecond != oldValue else {
                return
            }
            frameInterval = 1.0 / Double(preferredFramesPerSecond)
        }
    }
    private(set) var duration = 0.0
    private(set) var timestamp: CFTimeInterval = 0
    private(set) var targetTimestamp: CFTimeInterval = 0
    private var selector: Selector?
    private var displayLink: CVDisplayLink?
    private var frameInterval = 0.0
    private weak var delegate: NSObject?

    deinit {
        selector = nil
    }

    init(target: NSObject, selector sel: Selector) {
        super.init()
        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        guard let displayLink = displayLink else {
            return
        }
        self.delegate = target
        self.selector = sel
        CVDisplayLinkSetOutputHandler(displayLink) { [weak self] _, inNow, _, _, _ -> CVReturn in
            guard let self else {
                return kCVReturnSuccess
            }
            if frameInterval == 0 || frameInterval <= inNow.pointee.timestamp - self.timestamp {
                self.timestamp = Double(inNow.pointee.timestamp)
                // With the default preferredFramesPerSecond (0), frameInterval is 0 and
                // targetTimestamp == timestamp — consumers measuring elapsed time per tick
                // (MediaLink playout pacing) accumulate zero and never advance. Fall back
                // to the display's actual refresh period.
                let interval: Double
                if 0 < frameInterval {
                    interval = frameInterval
                } else if 0 < inNow.pointee.videoTimeScale && 0 < inNow.pointee.videoRefreshPeriod {
                    interval = Double(inNow.pointee.videoRefreshPeriod) / Double(inNow.pointee.videoTimeScale)
                } else {
                    interval = 1.0 / 60.0
                }
                self.targetTimestamp = self.timestamp + interval
                _ = self.delegate?.perform(self.selector, with: self)
            }
            return kCVReturnSuccess
        }
    }

    func add(to runloop: RunLoop, forMode mode: RunLoop.Mode) {
        guard let displayLink, !isPaused else {
            return
        }
        CVDisplayLinkStart(displayLink)
    }

    func invalidate() {
        guard let displayLink, isPaused else {
            return
        }
        CVDisplayLinkStop(displayLink)
    }
}

extension CVTimeStamp {
    @inlinable @inline(__always)
    var timestamp: Double {
        Double(self.hostTime) / Double(self.videoTimeScale)
    }
}

// swiftlint:enable attributes

#else
import QuartzCore
typealias DisplayLink = CADisplayLink
#endif

struct DisplayLinkTime {
    let timestamp: TimeInterval
    let targetTimestamp: TimeInterval
}

final class DisplayLinkChoreographer: NSObject {
    private static let preferredFramesPerSecond = 0

    var updateFrames: AsyncStream<DisplayLinkTime> {
        AsyncStream { continuation in
            self.continutation = continuation
        }
    }
    var preferredFramesPerSecond = DisplayLinkChoreographer.preferredFramesPerSecond {
        didSet {
            guard preferredFramesPerSecond != oldValue else {
                return
            }
            displayLink?.preferredFramesPerSecond = preferredFramesPerSecond
        }
    }
    private(set) var isRunning = false
    private var displayLink: DisplayLink? {
        didSet {
            oldValue?.invalidate()
            displayLink?.preferredFramesPerSecond = preferredFramesPerSecond
            displayLink?.isPaused = false
            displayLink?.add(to: .main, forMode: .common)
        }
    }
    private var continutation: AsyncStream<DisplayLinkTime>.Continuation?

    @objc
    private func update(displayLink: DisplayLink) {
        continutation?.yield(.init(timestamp: displayLink.timestamp, targetTimestamp: displayLink.targetTimestamp))
    }
}

extension DisplayLinkChoreographer: Runner {
    func startRunning() {
        guard !isRunning else {
            return
        }
        displayLink = DisplayLink(target: self, selector: #selector(self.update(displayLink:)))
        isRunning = true
    }

    func stopRunning() {
        guard isRunning else {
            return
        }
        isRunning = false
        displayLink = nil
        continutation?.finish()
    }
}
