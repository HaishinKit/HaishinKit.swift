#if canImport(AppKit)
import AppKit

extension NSColor {
    fileprivate convenience init?(hex: String) {
        var hex = hex
        if hex.hasPrefix("#") {
            hex.removeFirst()
        }

        guard hex.count == 8,
              let value = UInt32(hex, radix: 16) else {
            return nil
        }

        let a = CGFloat((value & 0xFF00_0000) >> 24) / 255.0
        let r = CGFloat((value & 0x00FF_0000) >> 16) / 255.0
        let g = CGFloat((value & 0x0000_FF00) >> 8) / 255.0
        let b = CGFloat(value & 0x0000_00FF) / 255.0

        self.init(red: r, green: g, blue: b, alpha: a)
    }

    fileprivate func toHexARGB() -> String? {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0

        self.getRed(&r, green: &g, blue: &b, alpha: &a)

        let ri = Int(round(r * 255))
        let gi = Int(round(g * 255))
        let bi = Int(round(b * 255))
        let ai = Int(round(a * 255))

        return String(format: "#%02X%02X%02X%02X", ai, ri, gi, bi)
    }
}
#endif

#if canImport(UIKit)
import UIKit

extension UIColor {
    fileprivate convenience init?(hex: String) {
        var hex = hex
        if hex.hasPrefix("#") {
            hex.removeFirst()
        }

        guard hex.count == 8,
              let value = UInt32(hex, radix: 16) else {
            return nil
        }

        let a = CGFloat((value & 0xFF00_0000) >> 24) / 255.0
        let r = CGFloat((value & 0x00FF_0000) >> 16) / 255.0
        let g = CGFloat((value & 0x0000_FF00) >> 8) / 255.0
        let b = CGFloat(value & 0x0000_00FF) / 255.0

        self.init(red: r, green: g, blue: b, alpha: a)
    }

    fileprivate func toHexRGBA() -> String? {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0

        guard self.getRed(&r, green: &g, blue: &b, alpha: &a) else {
            return nil
        }

        let ri = Int(round(r * 255))
        let gi = Int(round(g * 255))
        let bi = Int(round(b * 255))
        let ai = Int(round(a * 255))

        return String(format: "#%02X%02X%02X%02X", ai, ri, gi, bi)
    }
}
#endif

/// An object that manages offscreen rendering a text source.
public final class TextScreenObject: ScreenObject {
    public static let type: String = "text"

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

    override public var elements: [String: String] {
        get {
            var size: String?
            if let font = attributes?[.foregroundColor] as? NSFont {
                size = font.pointSize.description
            }
            var color: String?
            if let foregroundColor = attributes?[.foregroundColor] as? NSColor {
                color = foregroundColor.toHexARGB()
            }
            return [
                "value": string,
                "size": size ?? "32",
                "color": color ?? "#FFFFFFFF"
            ]
        }
        set {
            string = newValue["value"] ?? ""
            if let size = Double(newValue["size"] ?? "32.0") {
                attributes?[.font] = NSFont.boldSystemFont(ofSize: size)
            }
            if let color = NSColor(hex: newValue["color"] ?? "#FFFFFFFF") {
                attributes?[.foregroundColor] = color
            }
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

    override public var elements: [String: String] {
        get {
            var size: String?
            if let font = attributes?[.foregroundColor] as? UIFont {
                size = font.pointSize.description
            }
            var color: String?
            if let foregroundColor = attributes?[.foregroundColor] as? UIColor {
                color = foregroundColor.toHexRGBA()
            }
            return [
                "value": string,
                "size": size ?? "32",
                "color": color ?? "#FFFFFFFF"
            ]
        }
        set {
            string = newValue["value"] ?? ""
            if let size = Double(newValue["size"] ?? "32.0") {
                attributes?[.font] = UIFont.boldSystemFont(ofSize: size)
            }
            if let color = UIColor(hex: newValue["color"] ?? "#FFFFFFFF") {
                attributes?[.foregroundColor] = color
            }
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
