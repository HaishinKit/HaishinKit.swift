import CoreImage

private enum ImageSourceError: Error {
    case unsupported
    case invalidDataURL
    case invalidBase64
    case imageDecodingFailed
}

private protocol ImageSource {
    /// The original URL of the image source.
    var url: URL { get }

    /// Converts the image source into a CIImage.
    func toImage() throws -> CIImage
}

private enum ImageSourceFactory {
    static func parse(_ url: URL?) throws -> any ImageSource {
        guard let url else {
            throw ImageSourceError.unsupported
        }

        switch url.scheme {
        case "data":
            return DataImageSource(url: url)
        default:
            throw ImageSourceError.unsupported
        }
    }
}

private struct DataImageSource: ImageSource {
    let url: URL

    func toImage() throws -> CIImage {
        // data:[<mediatype>][;base64],<data>
        let urlString = url.absoluteString
        guard let base64Range = urlString.range(of: "base64,") else {
            throw ImageSourceError.invalidDataURL
        }
        let base64String = String(urlString[base64Range.upperBound...])
        guard let data = Data(base64Encoded: base64String) else {
            throw ImageSourceError.invalidBase64
        }
        guard let image = CIImage(data: data) else {
            throw ImageSourceError.imageDecodingFailed
        }
        return image
    }
}

/// An object that manages offscreen rendering a cgImage source.
public final class ImageScreenObject: ScreenObject {
    public static let type = "image"

    /// Specifies the image.
    public var cgImage: CGImage? {
        didSet {
            guard cgImage != oldValue else {
                return
            }
            invalidateLayout()
        }
    }

    override public func makeImage(_ renderer: some ScreenRenderer) -> CIImage? {
        let intersection = bounds.intersection(renderer.bounds)

        guard bounds != intersection else {
            if let cgImage {
                return CIImage(cgImage: cgImage)
            } else {
                return nil
            }
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

        if let cgImage = cgImage?.cropping(to: .init(origin: .init(x: x, y: y), size: intersection.size)) {
            return CIImage(cgImage: cgImage)
        } else {
            return nil
        }
    }

    override public func makeBounds(_ size: CGSize) -> CGRect {
        guard let cgImage else {
            return super.makeBounds(size)
        }
        return super.makeBounds(size == .zero ? cgImage.size : size)
    }
}
