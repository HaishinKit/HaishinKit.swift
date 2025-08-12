import Foundation

#if os(macOS)

import CoreVideo

// swiftlint:disable attributes

final class DisplayLink: NSObject {
    private static let preferredFramesPerSecond = 0

    var isPaused = false {
        didSet {
            guard let displayLink = displayLink, oldValue != isPaused else {
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
    private(set) var timestamp: CFTimeInterval = 0
    private(set) var targetTimestamp: CFTimeInterval = 0
    private var selector: Selector?
    private var displayLink: CVDisplayLink?
    private var frameInterval = 0.0
    private var duration: CFTimeInterval = 0
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
                self.targetTimestamp = self.timestamp + frameInterval
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

protocol ChoreographerDelegate: AnyObject {
    func choreographer(_ choreographer: some Choreographer, didFrame timestamp: TimeInterval, targetTimestamp: TimeInterval)
}

protocol Choreographer: Running {
    var isPaused: Bool { get set }
    var delegate: (any ChoreographerDelegate)? { get set }
}

final class DisplayLinkChoreographer: NSObject, Choreographer {
    private static let preferredFramesPerSecond = 0

    var isPaused: Bool {
        get {
            displayLink?.isPaused ?? true
        }
        set {
            displayLink?.isPaused = newValue
        }
    }
    weak var delegate: (any ChoreographerDelegate)?
    var isRunning: Atomic<Bool> = .init(false)
    var preferredFramesPerSecond = DisplayLinkChoreographer.preferredFramesPerSecond {
        didSet {
            guard let displayLink, preferredFramesPerSecond != oldValue else {
                return
            }
            displayLink.preferredFramesPerSecond = preferredFramesPerSecond
        }
    }
    private var displayLink: DisplayLink? {
        didSet {
            oldValue?.invalidate()
            displayLink?.isPaused = true
            displayLink?.preferredFramesPerSecond = preferredFramesPerSecond
            displayLink?.add(to: .main, forMode: .common)
        }
    }

    @objc
    private func update(displayLink: DisplayLink) {
        delegate?.choreographer(self, didFrame: displayLink.timestamp, targetTimestamp: displayLink.targetTimestamp)
    }
}

extension DisplayLinkChoreographer: Running {
    func startRunning() {
        displayLink = DisplayLink(target: self, selector: #selector(self.update(displayLink:)))
        isRunning.mutate { $0 = true }
    }

    func stopRunning() {
        displayLink = nil
        isRunning.mutate { $0 = false }
    }
}
