import AVFoundation
import CoreGraphics
import CoreImage
import Foundation

/// An object that manages offscreen rendering a streaming video track source.
public final class StreamScreenObject: ScreenObject, ChromaKeyProcessable {
    public var chromaKeyColor: CGColor?

    /// The video is displayed within a player layer’s bounds.
    public var videoGravity: AVLayerVideoGravity = .resizeAspect {
        didSet {
            guard videoGravity != oldValue else {
                return
            }
            invalidateLayout()
        }
    }

    private var sampleBuffer: CMSampleBuffer? {
        didSet {
            guard sampleBuffer != oldValue else {
                return
            }
            if sampleBuffer == nil {
                return
            }
            invalidateLayout()
        }
    }

    override var blendMode: ScreenObject.BlendMode {
        if 0.0 < cornerRadius || chromaKeyColor != nil {
            return .alpha
        }
        return .normal
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
}

extension StreamScreenObject: IOStreamObserver {
    // MARK: IOStreamObserver
    public func stream(_ stream: IOStream, didOutput audio: AVAudioBuffer, when: AVAudioTime) {
    }

    public func stream(_ stream: IOStream, didOutput video: CMSampleBuffer) {
        sampleBuffer = video
    }
}
