import AVFoundation
import Foundation

#if canImport(AppKit)
import AppKit
#endif

#if canImport(UIKit)
import UIKit
#endif

/// An interface a screen uses to inform its delegate.
public protocol ScreenDelegate: AnyObject {
    /// Tells the receiver to screen object layout phase.
    func screen(_ screen: Screen, willLayout time: CMTime)
}

/// An object that manages offscreen rendering a foundation.
public final class Screen: ScreenObjectContainerConvertible {
    /// The default screen size.
    public static let size = CGSize(width: 1280, height: 720)

    private static let lockFlags = CVPixelBufferLockFlags(rawValue: 0)
    private static let preferredTimescale: CMTimeScale = 1000000000

    /// The total of child counts.
    public var childCounts: Int {
        return root.childCounts
    }

    /// Specifies the delegate object.
    public weak var delegate: (any ScreenDelegate)?

    /// Specifies the video size to use when output a video.
    public var size: CGSize = Screen.size {
        didSet {
            guard size != oldValue else {
                return
            }
            renderer.bounds = .init(origin: .zero, size: size)
            CVPixelBufferPoolCreate(nil, nil, dynamicRangeMode.makePixelBufferAttributes(size), &pixelBufferPool)
        }
    }

    #if os(macOS)
    /// Specifies the background color.
    public var backgroundColor: CGColor = NSColor.black.cgColor {
        didSet {
            guard backgroundColor != oldValue else {
                return
            }
            renderer.backgroundColor = backgroundColor
        }
    }
    #else
    /// Specifies the background color.
    public var backgroundColor: CGColor = UIColor.black.cgColor {
        didSet {
            guard backgroundColor != oldValue else {
                return
            }
            renderer.backgroundColor = backgroundColor
        }
    }
    #endif

    var synchronizationClock: CMClock? {
        get {
            return renderer.synchronizationClock
        }
        set {
            renderer.synchronizationClock = newValue
        }
    }
    var dynamicRangeMode: DynamicRangeMode = .sdr {
        didSet {
            guard dynamicRangeMode != oldValue else {
                return
            }
            renderer = ScreenRendererByGPU(dynamicRangeMode: dynamicRangeMode)
            CVPixelBufferPoolCreate(nil, nil, dynamicRangeMode.makePixelBufferAttributes(size), &pixelBufferPool)
        }
    }
    private(set) var renderer: (any ScreenRenderer) = ScreenRendererByGPU(dynamicRangeMode: .sdr) {
        didSet {
            renderer.bounds = oldValue.bounds
            renderer.backgroundColor = oldValue.backgroundColor
            renderer.synchronizationClock = oldValue.synchronizationClock
        }
    }
    private(set) var targetTimestamp: TimeInterval = 0.0
    private(set) var videoTrackScreenObject = VideoScreenObject()
    private var videoCaptureLatency: TimeInterval = 0.0
    private(set) var root: ScreenObjectContainer = .init()
    private var outputFormat: CMFormatDescription?
    private var pixelBufferPool: CVPixelBufferPool? {
        didSet {
            outputFormat = nil
        }
    }
    private var presentationTimeStamp: CMTime = .zero

    /// Creates a screen object.
    public init() {
        try? addChild(videoTrackScreenObject)
        CVPixelBufferPoolCreate(nil, nil, dynamicRangeMode.makePixelBufferAttributes(size), &pixelBufferPool)
    }

    /// Adds the specified screen object as a child of the current screen object container.
    public func addChild(_ child: ScreenObject?) throws {
        try root.addChild(child)
    }

    /// Removes the specified screen object as a child of the current screen object container.
    public func removeChild(_ child: ScreenObject?) {
        root.removeChild(child)
    }

    /// Registers a video effect.
    public func registerVideoEffect(_ effect: some VideoEffect) -> Bool {
        return videoTrackScreenObject.registerVideoEffect(effect)
    }

    /// Unregisters a video effect.
    public func unregisterVideoEffect(_ effect: some VideoEffect) -> Bool {
        return videoTrackScreenObject.unregisterVideoEffect(effect)
    }

    public func findById(_ id: String) -> ScreenObject? {
        return root.findById(id)
    }

    func append(_ track: UInt8, buffer: CMSampleBuffer) {
        let screens: [VideoScreenObject] = root.getScreenObjects()
        for screen in screens where screen.track == track {
            screen.enqueue(buffer)
        }
    }

    func makeSampleBuffer(_ updateFrame: DisplayLinkTime) -> CMSampleBuffer? {
        defer {
            targetTimestamp = updateFrame.targetTimestamp
        }
        var pixelBuffer: CVPixelBuffer?
        pixelBufferPool?.createPixelBuffer(&pixelBuffer)
        guard let pixelBuffer else {
            return nil
        }
        if outputFormat == nil {
            CMVideoFormatDescriptionCreateForImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: pixelBuffer,
                formatDescriptionOut: &outputFormat
            )
        }
        guard let outputFormat else {
            return nil
        }
        if let dictionary = CVBufferCopyAttachments(pixelBuffer, .shouldNotPropagate) {
            CVBufferSetAttachments(pixelBuffer, dictionary, .shouldPropagate)
        }
        let presentationTimeStamp = CMTime(seconds: updateFrame.timestamp - videoCaptureLatency, preferredTimescale: Self.preferredTimescale)
        guard self.presentationTimeStamp <= presentationTimeStamp else {
            return nil
        }
        self.presentationTimeStamp = presentationTimeStamp
        var timingInfo = CMSampleTimingInfo(
            duration: CMTime(seconds: updateFrame.targetTimestamp - updateFrame.timestamp, preferredTimescale: Self.preferredTimescale),
            presentationTimeStamp: presentationTimeStamp,
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: outputFormat,
            sampleTiming: &timingInfo,
            sampleBufferOut: &sampleBuffer
        ) == noErr else {
            return nil
        }
        if let sampleBuffer {
            return render(sampleBuffer)
        } else {
            return nil
        }
    }

    func render(_ sampleBuffer: CMSampleBuffer) -> CMSampleBuffer {
        try? sampleBuffer.imageBuffer?.lockBaseAddress(Self.lockFlags)
        defer {
            try? sampleBuffer.imageBuffer?.unlockBaseAddress(Self.lockFlags)
        }
        renderer.presentationTimeStamp = sampleBuffer.presentationTimeStamp
        renderer.setTarget(sampleBuffer.imageBuffer)
        if let dimensions = sampleBuffer.formatDescription?.dimensions {
            root.size = dimensions.size
        }
        delegate?.screen(self, willLayout: sampleBuffer.presentationTimeStamp)
        root.layout(renderer)
        root.draw(renderer)
        renderer.render()
        return sampleBuffer
    }

    func setVideoCaptureLatency(_ presentationTimeStamp: CMTime) {
        guard 0 < targetTimestamp else {
            return
        }
        let hostPresentationTimeStamp = presentationTimeStamp.convertTime(from: synchronizationClock)
        let diff = ceil((targetTimestamp - hostPresentationTimeStamp.seconds) * 10000) / 10000
        videoCaptureLatency = diff
    }

    func reset() {
        let screens: [VideoScreenObject] = root.getScreenObjects()
        for screen in screens {
            screen.reset()
        }
    }
}
