import Accelerate
import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins

final class ScreenRendererByGPU: ScreenRenderer {
    var bounds: CGRect = .init(origin: .zero, size: Screen.size)
    let imageOptions: [CIImageOption: Any]?
    var synchronizationClock: CMClock?
    var presentationTimeStamp: CMTime = .zero

    let context: CIContext

    var backgroundColor = CGColor(red: 0x00, green: 0x00, blue: 0x00, alpha: 0x00) {
        didSet {
            guard backgroundColor != oldValue else {
                return
            }
            backgroundCIColor = CIColor(cgColor: backgroundColor)
        }
    }

    private var canvas: CIImage = .init()
    private var images: [ScreenObject: CIImage] = [:]
    private var pixelBuffer: CVPixelBuffer?
    private let dynamicRangeMode: DynamicRangeMode
    private var backgroundCIColor = CIColor()
    private var roundedRectangleFactory = RoundedRectangleFactory()

    init(dynamicRangeMode: DynamicRangeMode) {
        self.dynamicRangeMode = dynamicRangeMode
        context = dynamicRangeMode.makeCIContext()
        // HDR scenes can contain SDR and HLG inputs; preserve each source's colorimetry.
        if dynamicRangeMode == .sdr, let colorSpace = dynamicRangeMode.colorSpace {
            imageOptions = [.colorSpace: colorSpace]
        } else {
            imageOptions = nil
        }
    }

    func setTarget(_ pixelBuffer: CVPixelBuffer?) {
        guard let pixelBuffer else {
            return
        }
        self.pixelBuffer = pixelBuffer
        canvas = CIImage(color: backgroundCIColor).cropped(to: bounds)
    }

    func layout(_ screenObject: ScreenObject) {
        guard let image: CIImage = screenObject.makeImage(self) else {
            // Video sources can return nil between frames and should keep their previous image.
            if screenObject is ImageScreenObject {
                images.removeValue(forKey: screenObject)
            }
            return
        }
        if 0 < screenObject.cornerRadius {
            if let mask = roundedRectangleFactory.cornerRadius(screenObject.bounds.size, cornerRadius: screenObject.cornerRadius) {
                images[screenObject] = image.applyingFilter("CIBlendWithAlphaMask", parameters: [
                    "inputMaskImage": mask
                ])
            } else {
                images[screenObject] = image
            }
        } else {
            images[screenObject] = image
        }
    }

    func draw(_ screenObject: ScreenObject) {
        guard let image = images[screenObject] else {
            return
        }
        let origin = screenObject.bounds.origin
        canvas = image
            .transformed(by: .init(translationX: origin.x, y: bounds.maxY - origin.y - screenObject.bounds.height))
            .composited(over: canvas)
    }

    func removeImages(for screenObject: ScreenObject) {
        images.removeValue(forKey: screenObject)
        if let container = screenObject as? ScreenObjectContainer {
            for child in container.children {
                removeImages(for: child)
            }
        }
    }

    func render() {
        guard let pixelBuffer else {
            return
        }
        context.render(canvas, to: pixelBuffer, bounds: canvas.extent, colorSpace: dynamicRangeMode.colorSpace)
        dynamicRangeMode.attach(pixelBuffer)
    }
}
