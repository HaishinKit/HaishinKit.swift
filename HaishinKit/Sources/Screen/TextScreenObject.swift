#if canImport(AppKit)
import AppKit
#endif

#if canImport(UIKit)
import UIKit
#endif

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

    override public func makeImage(_ renderer: some ScreenRenderer) -> CIImage? {
        guard let context, let framesetter else {
            return nil
        }
        let path = CGPath(rect: .init(origin: .zero, size: bounds.size), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, .init(), path, nil)
        context.clear(context.boundingBoxOfPath)
        CTFrameDraw(frame, context)
        if let cgImage = context.makeImage() {
            return CIImage(cgImage: cgImage)
        } else {
            return nil
        }
    }
}
