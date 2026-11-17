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
    override public class var type: String { "image" }

    private enum Keys {
        static let source = "source"
    }

    /// Specifies the image.
    public var ciImage: CIImage? {
        didSet {
            guard ciImage != oldValue else {
                return
            }
            invalidateLayout()
        }
    }

    override public var elements: [String: String] {
        get {
            return [
                Keys.source: source ?? ""
            ]
        }
        set {
            do {
                try setSource(newValue[Keys.source])
            } catch {
                logger.warn(error)
            }
        }
    }

    private var source: String?

    override public func makeImage(_ renderer: some ScreenRenderer) -> CIImage? {
        guard let ciImage, !bounds.isEmpty else {
            return nil
        }
        let extent = ciImage.extent
        let visible = bounds.intersection(renderer.bounds)
        guard !extent.isEmpty, !extent.isInfinite, !visible.isEmpty else {
            return nil
        }

        let image = ciImage
            .transformed(by: .init(translationX: -extent.minX, y: -extent.minY))
            .transformed(by: .init(scaleX: bounds.width / extent.width, y: bounds.height / extent.height))
        // Screen bounds use a top-left origin. Core Image crops from the bottom left.
        return image.cropped(to: CGRect(
            x: visible.minX - bounds.minX,
            y: bounds.maxY - visible.maxY,
            width: visible.width,
            height: visible.height
        ))
    }

    override public func makeBounds(_ size: CGSize) -> CGRect {
        guard let ciImage else {
            return super.makeBounds(size)
        }
        return super.makeBounds(size == .zero ? ciImage.extent.size : size)
    }

    func setSource(_ source: String?) throws {
        self.source = source
        let imageSource = try ImageSourceFactory.parse(URL(string: source ?? ""))
        ciImage = try imageSource.toImage()
    }
}
