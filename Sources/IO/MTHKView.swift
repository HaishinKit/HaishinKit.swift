#if os(iOS) || os(tvOS) || os(macOS)

import AVFoundation
import MetalKit

#if os(macOS)
private typealias View = NSView
#else
private typealias View = UIView
#endif

/**
 * A view that displays a video content of a NetStream object which uses Metal api.
 */
public class MTHKView: MTKView {
    /// Specifies how the video is displayed within a player layer’s bounds.
    public var videoGravity: AVLayerVideoGravity = .resizeAspect

    #if os(iOS) || os(macOS)
    /// Specifies the orientation of AVCaptureVideoOrientation.
    public var videoOrientation: AVCaptureVideoOrientation = .portrait {
        didSet {
            (captureVideoPreview as? IOCaptureVideoPreview)?.videoOrientation = videoOrientation
        }
    }
    #endif

    /// Specifies the capture video preview enabled or not.
    @available(tvOS 17.0, *)
    public var isCaptureVideoPreviewEnabled: Bool {
        get {
            captureVideoPreview != nil
        }
        set {
            guard isCaptureVideoPreviewEnabled != newValue else {
                return
            }
            if Thread.isMainThread {
                captureVideoPreview = newValue ? IOCaptureVideoPreview(self) : nil
            } else {
                DispatchQueue.main.async {
                    self.captureVideoPreview = newValue ? IOCaptureVideoPreview(self) : nil
                }
            }
        }
    }

    /// Specifies the preview is mirror or not. Default value is `false`
    public var isMirrored: Bool = false

    private var displayImage: CIImage?
    private lazy var commandQueue: (any MTLCommandQueue)? = {
        return device?.makeCommandQueue()
    }()

    private var context: CIContext?

    private var captureVideoPreview: View? {
        willSet {
            captureVideoPreview?.removeFromSuperview()
        }
        didSet {
            captureVideoPreview.map {
                addSubview($0)
                sendSubviewToBack($0)
            }
        }
    }

    private weak var currentStream: IOStream? {
        didSet {
            currentStream.map {
                $0.view = self
            }
        }
    }

    /// Initializes and returns a newly allocated view object with the specified frame rectangle.
    public init(frame: CGRect) {
        super.init(frame: frame, device: MTLCreateSystemDefaultDevice())
        awakeFromNib()
    }

    /// Returns an object initialized from data in a given unarchiver.
    public required init(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        self.device = MTLCreateSystemDefaultDevice()
    }

    /// Prepares the receiver for service after it has been loaded from an Interface Builder archive, or nib file.
    override open func awakeFromNib() {
        super.awakeFromNib()
        framebufferOnly = false
        enableSetNeedsDisplay = true
        if let device {
            context = CIContext(mtlDevice: device, options: [.cacheIntermediates: false, .name: "MTHKView"])
        }
    }

    override open func draw(_ rect: CGRect) {
        guard
            let context,
            let currentDrawable = currentDrawable,
            let commandBuffer = commandQueue?.makeCommandBuffer() else {
            return
        }
        if
            let currentRenderPassDescriptor = currentRenderPassDescriptor,
            let renderCommandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: currentRenderPassDescriptor) {
            renderCommandEncoder.endEncoding()
        }
        guard let displayImage else {
            commandBuffer.present(currentDrawable)
            commandBuffer.commit()
            return
        }
        var scaleX: CGFloat = 0
        var scaleY: CGFloat = 0
        var translationX: CGFloat = 0
        var translationY: CGFloat = 0
        switch videoGravity {
        case .resize:
            scaleX = drawableSize.width / displayImage.extent.width
            scaleY = drawableSize.height / displayImage.extent.height
        case .resizeAspect:
            let scale: CGFloat = min(drawableSize.width / displayImage.extent.width, drawableSize.height / displayImage.extent.height)
            scaleX = scale
            scaleY = scale
            translationX = (drawableSize.width - displayImage.extent.width * scale) / scaleX / 2
            translationY = (drawableSize.height - displayImage.extent.height * scale) / scaleY / 2
        case .resizeAspectFill:
            let scale: CGFloat = max(drawableSize.width / displayImage.extent.width, drawableSize.height / displayImage.extent.height)
            scaleX = scale
            scaleY = scale
            translationX = (drawableSize.width - displayImage.extent.width * scale) / scaleX / 2
            translationY = (drawableSize.height - displayImage.extent.height * scale) / scaleY / 2
        default:
            break
        }

        var scaledImage = displayImage

        if isMirrored {
            let mirror = CGAffineTransform(scaleX: -1, y: 1)
                .translatedBy(x: -scaledImage.extent.width, y: 0)
            scaledImage = scaledImage.transformed(by: mirror)
        }

        scaledImage = scaledImage
            .transformed(by: CGAffineTransform(translationX: translationX, y: translationY))
            .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        let destination = CIRenderDestination(
            width: Int(drawableSize.width),
            height: Int(drawableSize.height),
            pixelFormat: colorPixelFormat,
            commandBuffer: commandBuffer,
            mtlTextureProvider: { () -> (any MTLTexture) in
                return currentDrawable.texture
            })

        _ = try? context.startTask(toRender: scaledImage, to: destination)

        commandBuffer.present(currentDrawable)
        commandBuffer.commit()
    }
}

extension MTHKView: IOStreamView {
    // MARK: IOStreamView
    public func attachStream(_ stream: IOStream?) {
        if Thread.isMainThread {
            currentStream = stream
        } else {
            DispatchQueue.main.async {
                self.currentStream = stream
            }
        }
    }

    public func enqueue(_ sampleBuffer: CMSampleBuffer?) {
        if Thread.isMainThread {
            displayImage = sampleBuffer?.imageBuffer?.makeCIImage()
            #if os(macOS)
            self.needsDisplay = true
            #else
            self.setNeedsDisplay()
            #endif
        } else {
            DispatchQueue.main.async {
                self.enqueue(sampleBuffer)
            }
        }
    }
}

#endif
