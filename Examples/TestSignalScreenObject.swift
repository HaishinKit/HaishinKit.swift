import CoreGraphics
import CoreImage
import CoreMedia
import CoreText
import Foundation
import HaishinKit
#if canImport(UIKit)
import UIKit
#endif

/// Shared video-only test pattern for example scenes.
final class TestSignalScreenObject: ScreenObject {
    nonisolated static let typeIdentifier = "testSignal"
    override class var type: String { typeIdentifier }

    private let frameRate = 30
    private var startTime: Double?
    private var bitmap: CGContext?
    private var cachedFrame: Int64?
    private var cachedImage: CGImage?
    private let patternSize = CGSize(width: 1280, height: 720)

    override func makeBounds(_ size: CGSize) -> CGRect {
        super.makeBounds(size == .zero ? patternSize : size)
    }

    func image(at time: CMTime) -> CGImage? {
        if bitmap == nil {
            bitmap = CGContext(data: nil, width: 1280, height: 720, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        }
        guard let bitmap else { return nil }
        let timestamp = time.seconds
        if timestamp.isFinite, startTime == nil || timestamp < (startTime ?? timestamp) { startTime = timestamp }
        let elapsed = timestamp.isFinite ? max(0, min(Double(Int32.max), timestamp - (startTime ?? timestamp))) : 0
        let frame = Int64(elapsed * Double(max(1, min(240, frameRate))))
        if cachedFrame == frame { return cachedImage }
        TestSignalPattern.draw(in: bitmap, width: 1280, height: 720, frame: frame, frameRate: frameRate)
        cachedImage = bitmap.makeImage()
        cachedFrame = cachedImage == nil ? nil : frame
        return cachedImage
    }

    override func makeImage(_ renderer: some ScreenRenderer) -> CIImage? {
        guard !bounds.isEmpty, let image = image(at: renderer.presentationTimeStamp) else { return nil }
        let visible = bounds.intersection(renderer.bounds)
        guard !visible.isEmpty else { return nil }
        return CIImage(cgImage: image)
            .transformed(by: .init(scaleX: bounds.width / patternSize.width, y: bounds.height / patternSize.height))
            .cropped(to: CGRect(x: visible.minX - bounds.minX, y: bounds.maxY - visible.maxY,
                width: visible.width, height: visible.height))
    }
}

/// The bitmap drawing is also used by the existing timed test source.
enum TestSignalPattern {
    static func draw(in context: CGContext, width: Int, height: Int, frame: Int64, frameRate: Int = 30, subtitle: String = "") {
        guard width > 24, height > 160 else { return }
        context.saveGState()
        defer { context.restoreGState() }
        let colors: [(CGFloat, CGFloat, CGFloat)] = [(1,1,1), (1,1,0), (0,1,1), (0,1,0), (1,0,1), (1,0,0), (0,0,1), (0,0,0)]
        for (index, color) in colors.enumerated() {
            context.setFillColor(red: color.0, green: color.1, blue: color.2, alpha: 1)
            context.fill(CGRect(x: index * width / 8, y: 0, width: width / 8, height: height))
        }
        context.setFillColor(gray: 0, alpha: 0.85)
        context.fill(CGRect(x: 0, y: height - 140, width: width, height: 140))
        context.setFillColor(gray: 1, alpha: 1)
        let range = Int64(width - 24)
        let position = ((frame % range + range) % range * 9) % range
        context.fill(CGRect(x: Int(position), y: 10, width: 24, height: height - 160))
        let font = CTFontCreateWithName("Menlo" as CFString, 30, nil)
        let lines = ["HaishinKit  •  \(width) × \(height)  •  \(frameRate) fps  •  #\(frame)", subtitle]
        context.textMatrix = .identity
        for (index, value) in lines.enumerated() where !value.isEmpty {
            let text = NSAttributedString(string: value, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1)
            ])
            context.textPosition = CGPoint(x: 30, y: height - 55 - index * 45)
            CTLineDraw(CTLineCreateWithAttributedString(text as CFAttributedString), context)
        }
    }
}

/// Adds example-defined nodes while delegating built-in and opaque nodes to the library factory.
@ScreenActor
enum ExampleScreenObjectFactory {
    static func make(_ snapshot: ScreenObjectSnapshot) -> ScreenObject? {
        let object: ScreenObject
        switch snapshot.type {
        case TestSignalScreenObject.typeIdentifier:
            object = TestSignalScreenObject(id: snapshot.id)
        case "screen", "container":
            let container = ScreenObjectContainer(id: snapshot.id)
            for child in snapshot.children { try? container.addChild(make(child)) }
            object = container
        default:
            return ScreenObjectFactory().make(snapshot)
        }
        object.size = snapshot.size.cgSize
        object.isVisible = snapshot.isVisible
        object.cornerRadius = CGFloat(snapshot.cornerRadius ?? 0)
        object.elements = snapshot.elements
        object.horizontalAlignment = .init(rawValue: snapshot.horizontalAlignment) ?? .left
        object.verticalAlignment = .init(rawValue: snapshot.verticalAlignment) ?? .top
        object.layoutMargin = .init(top: CGFloat(snapshot.layoutMargin.top), left: CGFloat(snapshot.layoutMargin.left),
            bottom: CGFloat(snapshot.layoutMargin.bottom), right: CGFloat(snapshot.layoutMargin.right))
        return object
    }
}

/// Invalidates animated nodes on the compositor's own frame callback, without another timer.
@ScreenActor
final class TestSignalSceneDelegate: @preconcurrency ScreenDelegate {
    private weak var previous: (any ScreenDelegate)?
    private var signals: [TestSignalScreenObject] = []

    nonisolated init() {}

    func attach(to screen: Screen) {
        func nodes(_ node: ScreenObjectSnapshot) -> [ScreenObjectSnapshot] { [node] + node.children.flatMap(nodes) }
        signals = nodes(ScreenObjectSnapshotFactory().make(screen)).compactMap { screen.findById($0.id) as? TestSignalScreenObject }
        guard !signals.isEmpty else { detach(from: screen); return }
        if screen.delegate !== self { previous = screen.delegate }
        screen.delegate = self
    }

    func detach(from screen: Screen) {
        if screen.delegate === self { screen.delegate = previous }
        previous = nil
        signals.removeAll()
    }

    func screen(_ screen: Screen, willLayout time: CMTime) {
        previous?.screen(screen, willLayout: time)
        for signal in signals {
            var current: ScreenObject? = signal
            var ancestors: [ScreenObject] = []
            while let object = current {
                ancestors.append(object)
                current = object.parent
            }
            guard ancestors.allSatisfy(\.isVisible) else { continue }
            // A nested container must also relayout before its animated descendant is visited.
            for object in ancestors where object.parent != nil { object.invalidateLayout() }
        }
    }
}
