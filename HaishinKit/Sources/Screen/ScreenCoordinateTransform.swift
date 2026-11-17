import AVFoundation
import CoreGraphics

/// Maps between composition pixels and preview-local coordinates, both with a top-left origin.
public struct ScreenCoordinateTransform: Sendable {
    private let scale: CGSize
    private let offset: CGPoint

    /// Creates a transform for a centered preview. Recreate it when either size changes.
    public init?(screenSize: CGSize, previewSize: CGSize, videoGravity: AVLayerVideoGravity = .resizeAspect) {
        let x = previewSize.width / screenSize.width
        let y = previewSize.height / screenSize.height
        guard x.isFinite, y.isFinite, x > 0, y > 0,
              screenSize.width > 0, screenSize.height > 0 else {
            return nil
        }
        switch videoGravity {
        case .resize:
            scale = CGSize(width: x, height: y)
        case .resizeAspectFill:
            scale = CGSize(width: max(x, y), height: max(x, y))
        default:
            scale = CGSize(width: min(x, y), height: min(x, y))
        }
        offset = CGPoint(
            x: (previewSize.width - screenSize.width * scale.width) / 2,
            y: (previewSize.height - screenSize.height * scale.height) / 2
        )
    }

    /// Converts a preview point without clamping points in letterbox bars.
    public func toScreen(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - offset.x) / scale.width, y: (point.y - offset.y) / scale.height)
    }

    /// Converts a composition point without clipping cropped content.
    public func toPreview(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x * scale.width + offset.x, y: point.y * scale.height + offset.y)
    }

    /// Converts a composition rectangle without clipping cropped content.
    public func toPreview(_ rect: CGRect) -> CGRect {
        CGRect(
            origin: toPreview(rect.origin),
            size: CGSize(width: rect.width * scale.width, height: rect.height * scale.height)
        )
    }
}
