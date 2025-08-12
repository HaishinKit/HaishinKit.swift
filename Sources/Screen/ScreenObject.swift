import Accelerate
import AVFoundation
import CoreImage
import CoreMedia
import Foundation
import VideoToolbox

#if canImport(AppKit)
import AppKit
#endif

#if canImport(UIKit)
import UIKit
#endif

/// The ScreenObject class is the abstract class for all objects that are rendered on the screen.
open class ScreenObject {
    /// The horizontal alignment for the screen object.
    public enum HorizontalAlignment {
        /// A guide that marks the left edge of the screen object.
        case left
        /// A guide that marks the borizontal center of the screen object.
        case center
        /// A guide that marks the right edge of the screen object.
        case right
    }

    /// The vertical alignment for the screen object.
    public enum VerticalAlignment {
        /// A guide that marks the top edge of the screen object.
        case top
        /// A guide that marks the vertical middle of the screen object.
        case middle
        /// A guide that marks the bottom edge of the screen object.
        case bottom
    }

    enum BlendMode {
        case normal
        case alpha
    }

    /// The screen object container that contains this screen object
    public internal(set) weak var parent: ScreenObjectContainer?

    /// Specifies the size rectangle.
    public var size: CGSize = .zero {
        didSet {
            guard size != oldValue else {
                return
            }
            shouldInvalidateLayout = true
        }
    }

    /// The bounds rectangle.
    public internal(set) var bounds: CGRect = .zero

    /// Specifies the visibility of the object.
    public var isVisible = true

    #if os(macOS)
    /// Specifies the default spacing to laying out content in the screen object.
    public var layoutMargin: NSEdgeInsets = .init(top: 0, left: 0, bottom: 0, right: 0)
    #else
    /// Specifies the default spacing to laying out content in the screen object.
    public var layoutMargin: UIEdgeInsets = .init(top: 0, left: 0, bottom: 0, right: 0)
    #endif

    /// Specifies the radius to use when drawing rounded corners.
    public var cornerRadius: CGFloat = 0.0

    /// Specifies the alignment position along the vertical axis.
    public var verticalAlignment: VerticalAlignment = .top

    /// Specifies the alignment position along the horizontal axis.
    public var horizontalAlignment: HorizontalAlignment = .left

    var blendMode: BlendMode {
        .alpha
    }

    var shouldInvalidateLayout = true

    /// Creates a screen object.
    public init() {
    }

    /// Invalidates the current layout and triggers a layout update.
    public func invalidateLayout() {
        shouldInvalidateLayout = true
    }

    /// Makes cgImage for offscreen image.
    open func makeImage(_ renderer: some ScreenRenderer) -> CGImage? {
        return nil
    }

    /// Makes screen object bounds for offscreen image.
    open func makeBounds(_ size: CGSize) -> CGRect {
        guard let parent else {
            return .init(origin: .zero, size: self.size)
        }

        let width = size.width == 0 ? max(parent.bounds.width - layoutMargin.left - layoutMargin.right + size.width, 0) : size.width
        let height = size.height == 0 ? max(parent.bounds.height - layoutMargin.top - layoutMargin.bottom + size.height, 0) : size.height

        let parentX = parent.bounds.origin.x
        let parentWidth = parent.bounds.width
        let x: CGFloat
        switch horizontalAlignment {
        case .center:
            x = parentX + (parentWidth - width) / 2
        case .left:
            x = parentX + layoutMargin.left
        case .right:
            x = parentX + (parentWidth - width) - layoutMargin.right
        }

        let parentY = parent.bounds.origin.y
        let parentHeight = parent.bounds.height
        let y: CGFloat
        switch verticalAlignment {
        case .top:
            y = parentY + layoutMargin.top
        case .middle:
            y = parentY + (parentHeight - height) / 2
        case .bottom:
            y = parentY + (parentHeight - height) - layoutMargin.bottom
        }

        return .init(x: x, y: y, width: width, height: height)
    }

    func layout(_ renderer: some ScreenRenderer) {
        bounds = makeBounds(size)
        renderer.layout(self)
        shouldInvalidateLayout = false
    }

    func draw(_ renderer: some ScreenRenderer) {
        renderer.draw(self)
    }
}

extension ScreenObject: Hashable {
    // MARK: Hashable
    public static func == (lhs: ScreenObject, rhs: ScreenObject) -> Bool {
        lhs === rhs
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}

/// An object that manages offscreen rendering a cgImage source.
public final class ImageScreenObject: ScreenObject {
    /// Specifies the image.
    public var cgImage: CGImage? {
        didSet {
            guard cgImage != oldValue else {
                return
            }
            invalidateLayout()
        }
    }

    override public func makeImage(_ renderer: some ScreenRenderer) -> CGImage? {
        let intersection = bounds.intersection(renderer.bounds)

        guard bounds != intersection else {
            return cgImage
        }

        // Handling when the drawing area is exceeded.
        let x: CGFloat
        switch horizontalAlignment {
        case .left:
            x = bounds.origin.x
        case .center:
            x = bounds.origin.x / 2
        case .right:
            x = 0.0
        }

        let y: CGFloat
        switch verticalAlignment {
        case .top:
            y = 0.0
        case .middle:
            y = abs(bounds.origin.y) / 2
        case .bottom:
            y = abs(bounds.origin.y)
        }

        return cgImage?.cropping(to: .init(origin: .init(x: x, y: y), size: intersection.size))
    }

    override public func makeBounds(_ size: CGSize) -> CGRect {
        guard let cgImage else {
            return super.makeBounds(size)
        }
        return super.makeBounds(size == .zero ? cgImage.size : size)
    }
}

/// An object that manages offscreen rendering a video track source.
public final class VideoTrackScreenObject: ScreenObject, ChromaKeyProcessable {
    static let capacity: Int = 3
    public var chromaKeyColor: CGColor?

    /// Specifies the track number how the displays the visual content.
    public var track: UInt8 = 0 {
        didSet {
            guard track != oldValue else {
                return
            }
            invalidateLayout()
        }
    }

    /// A value that specifies how the video is displayed within a player layer’s bounds.
    public var videoGravity: AVLayerVideoGravity = .resizeAspect {
        didSet {
            guard videoGravity != oldValue else {
                return
            }
            invalidateLayout()
        }
    }

    public var frameRate: Int {
        frameTracker.frameRate
    }

    override var blendMode: ScreenObject.BlendMode {
        if 0.0 < cornerRadius || chromaKeyColor != nil {
            return .alpha
        }
        return .normal
    }

    private var queue: TypedBlockQueue<CMSampleBuffer>?
    private var effects: [VideoEffect] = .init()
    private var frameTracker = FrameTracker()

    /// Create a screen object.
    override public init() {
        super.init()
        horizontalAlignment = .center
        do {
            queue = try TypedBlockQueue(capacity: Self.capacity, handlers: .outputPTSSortedSampleBuffers)
        } catch {
            logger.error(error)
        }
    }

    /// Registers a video effect.
    public func registerVideoEffect(_ effect: VideoEffect) -> Bool {
        if effects.contains(where: { $0 === effect }) {
            return false
        }
        effects.append(effect)
        return true
    }

    /// Unregisters a video effect.
    public func unregisterVideoEffect(_ effect: VideoEffect) -> Bool {
        if let index = effects.firstIndex(where: { $0 === effect }) {
            effects.remove(at: index)
            return true
        }
        return false
    }

    override public func makeImage(_ renderer: some ScreenRenderer) -> CGImage? {
        guard let sampleBuffer = queue?.dequeue(renderer.presentationTimeStamp),
              let pixelBuffer = sampleBuffer.imageBuffer else {
            return nil
        }
        frameTracker.update(sampleBuffer.presentationTimeStamp)
        // Resizing before applying the filter for performance optimization.
        var image = CIImage(cvPixelBuffer: pixelBuffer).transformed(by: videoGravity.scale(
            bounds.size,
            image: pixelBuffer.size
        ))
        if effects.isEmpty {
            return renderer.context.createCGImage(image, from: videoGravity.region(bounds, image: image.extent))
        } else {
            for effect in effects {
                image = effect.execute(image, info: sampleBuffer)
            }
            return renderer.context.createCGImage(image, from: videoGravity.region(bounds, image: image.extent))
        }
    }

    override public func makeBounds(_ size: CGSize) -> CGRect {
        guard parent != nil, let image = queue?.head?.formatDescription?.dimensions.size else {
            return super.makeBounds(size)
        }
        let bounds = super.makeBounds(size)
        switch videoGravity {
        case .resizeAspect:
            let scale = min(bounds.size.width / image.width, bounds.size.height / image.height)
            let scaleSize = CGSize(width: image.width * scale, height: image.height * scale)
            return super.makeBounds(scaleSize)
        case .resizeAspectFill:
            return bounds
        default:
            return bounds
        }
    }

    override public func draw(_ renderer: some ScreenRenderer) {
        super.draw(renderer)
        if queue?.isEmpty == false {
            invalidateLayout()
        }
    }

    func enqueue(_ sampleBuffer: CMSampleBuffer) {
        try? queue?.enqueue(sampleBuffer)
        invalidateLayout()
    }

    func reset() {
        frameTracker.clear()
        try? queue?.reset()
        invalidateLayout()
    }
}

/// An object that manages offscreen rendering a text source.
public final class TextScreenObject: ScreenObject {
    /// Specifies the text value.
    public var string: String = "" {
        didSet {
            guard string != oldValue else {
                return
            }
            invalidateLayout()
        }
    }

    #if os(macOS)
    /// Specifies the attributes for strings.
    public var attributes: [NSAttributedString.Key: Any]? = [
        .font: NSFont.boldSystemFont(ofSize: 32),
        .foregroundColor: NSColor.white
    ] {
        didSet {
            invalidateLayout()
        }
    }
    #else
    /// Specifies the attributes for strings.
    public var attributes: [NSAttributedString.Key: Any]? = [
        .font: UIFont.boldSystemFont(ofSize: 32),
        .foregroundColor: UIColor.white
    ] {
        didSet {
            invalidateLayout()
        }
    }
    #endif

    override public var bounds: CGRect {
        didSet {
            guard bounds != oldValue else {
                return
            }
            context = CGContext(
                data: nil,
                width: Int(bounds.width),
                height: Int(bounds.height),
                bitsPerComponent: 8,
                bytesPerRow: Int(bounds.width) * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue).rawValue
            )
        }
    }

    private var context: CGContext?
    private var framesetter: CTFramesetter?

    override public func makeBounds(_ size: CGSize) -> CGRect {
        guard !string.isEmpty else {
            self.framesetter = nil
            return .zero
        }
        let bounds = super.makeBounds(size)
        let attributedString = NSAttributedString(string: string, attributes: attributes)
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
        let frameSize = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            .init(),
            nil,
            bounds.size,
            nil
        )
        self.framesetter = framesetter
        return super.makeBounds(frameSize)
    }

    override public func makeImage(_ renderer: some ScreenRenderer) -> CGImage? {
        guard let context, let framesetter else {
            return nil
        }
        let path = CGPath(rect: .init(origin: .zero, size: bounds.size), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, .init(), path, nil)
        context.clear(context.boundingBoxOfPath)
        CTFrameDraw(frame, context)
        return context.makeImage()
    }
}

#if !os(visionOS)
/// An object that manages offscreen rendering an asset resource.
public final class AssetScreenObject: ScreenObject, ChromaKeyProcessable {
    public var chromaKeyColor: CGColor?

    public var isReading: Bool {
        return reader?.status == .reading
    }

    /// A value that specifies how the video is displayed within a player layer’s bounds.
    public var videoGravity: AVLayerVideoGravity = .resizeAspect {
        didSet {
            guard videoGravity != oldValue else {
                return
            }
            invalidateLayout()
        }
    }

    private var reader: AVAssetReader? {
        didSet {
            if let oldValue, oldValue.status == .reading {
                oldValue.cancelReading()
            }
        }
    }

    private var sampleBuffer: CMSampleBuffer? {
        didSet {
            guard sampleBuffer != oldValue else {
                return
            }
            if sampleBuffer == nil {
                cancelReading()
                return
            }
            invalidateLayout()
        }
    }

    private var startedAt: CMTime = .zero
    private var videoTrackOutput: AVAssetReaderTrackOutput?
    private var outputSettings = [
        kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA
    ] as [String: Any]

    /// Prepares the asset reader to start reading.
    public func startReading(_ asset: AVAsset) throws {
        reader = try AVAssetReader(asset: asset)
        guard let reader else {
            return
        }
        let videoTrack = asset.tracks(withMediaType: .video).first
        if let videoTrack {
            let videoTrackOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: outputSettings)
            videoTrackOutput.alwaysCopiesSampleData = false
            reader.add(videoTrackOutput)
            self.videoTrackOutput = videoTrackOutput
        }
        startedAt = CMClock.hostTimeClock.time
        reader.startReading()
        sampleBuffer = videoTrackOutput?.copyNextSampleBuffer()
    }

    /// Cancels and stops the reader's output.
    public func cancelReading() {
        reader = nil
        sampleBuffer = nil
        videoTrackOutput = nil
    }

    override public func makeBounds(_ size: CGSize) -> CGRect {
        guard parent != nil, let image = sampleBuffer?.formatDescription?.dimensions.size else {
            return super.makeBounds(size)
        }
        let bounds = super.makeBounds(size)
        switch videoGravity {
        case .resizeAspect:
            let scale = min(bounds.size.width / image.width, bounds.size.height / image.height)
            let scaleSize = CGSize(width: image.width * scale, height: image.height * scale)
            return super.makeBounds(scaleSize)
        case .resizeAspectFill:
            return bounds
        default:
            return bounds
        }
    }

    override public func makeImage(_ renderer: some ScreenRenderer) -> CGImage? {
        guard let sampleBuffer, let pixelBuffer = sampleBuffer.imageBuffer else {
            return nil
        }
        let image = CIImage(cvPixelBuffer: pixelBuffer).transformed(by: videoGravity.scale(
            bounds.size,
            image: pixelBuffer.size
        ))
        return renderer.context.createCGImage(image, from: videoGravity.region(bounds, image: image.extent))
    }

    override func draw(_ renderer: some ScreenRenderer) {
        super.draw(renderer)
        let duration = CMClock.hostTimeClock.time - startedAt
        if let sampleBuffer, sampleBuffer.presentationTimeStamp <= duration {
            self.sampleBuffer = videoTrackOutput?.copyNextSampleBuffer()
        }
    }
}
#endif
