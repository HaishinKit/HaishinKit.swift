#if os(iOS) || os(tvOS) || os(macOS)

import AVFoundation
import MetalKit

/// A view that displays a video content of a NetStream object which uses Metal api.
public class MTHKView: MTKView {
    /// Specifies how the video is displayed within a player layer’s bounds.
    public var videoGravity: AVLayerVideoGravity = .resizeAspect
    public var videoTrackId: UInt8? = UInt8.max
    public var audioTrackId: UInt8?
    /// The explicitly selected display range. HDR expects BT.2100 HLG video.
    public private(set) var dynamicRangeMode: DynamicRangeMode = .sdr
    private var displayImage: CIImage?
    private var outputColorSpace: CGColorSpace?
    private var restoreSDRConfiguration: (@MainActor () -> Void)?
    private lazy var commandQueue: (any MTLCommandQueue)? = {
        return device?.makeCommandQueue()
    }()
    private var context: CIContext?
    private var effects: [any VideoEffect] = .init()

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
    override public func awakeFromNib() {
        super.awakeFromNib()
        Task { @MainActor in
            framebufferOnly = false
            enableSetNeedsDisplay = true
            if let device {
                context = CIContext(mtlDevice: device, options: [.cacheIntermediates: false, .name: "MTHKView", .workingFormat: CIFormat.RGBAh.rawValue])
            }
        }
    }

    /// Redraws the view’s contents.
    override public func draw(_ rect: CGRect) {
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

        var scaledImage: CIImage = displayImage
        for effect in effects {
            scaledImage = effect.execute(scaledImage)
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

        _ = try? startRendering(scaledImage, to: destination, using: context)

        commandBuffer.present(currentDrawable)
        commandBuffer.commit()
    }

    func startRendering(_ image: CIImage, to destination: CIRenderDestination, using context: CIContext) throws -> CIRenderTask {
        if let outputColorSpace {
            destination.colorSpace = outputColorSpace
        }
        return try context.startTask(toRender: image, to: destination)
    }

    /// Registers a video effect.
    public func registerVideoEffect(_ effect: some VideoEffect) -> Bool {
        if effects.contains(where: { $0 === effect }) {
            return false
        }
        effects.append(effect)
        return true
    }

    /// Unregisters a video effect.
    public func unregisterVideoEffect(_ effect: some VideoEffect) -> Bool {
        if let index = effects.firstIndex(where: { $0 === effect }) {
            effects.remove(at: index)
            return true
        }
        return false
    }

    /// Sets the display range to match the mixer or the expected incoming video.
    ///
    /// Call this explicitly; incoming sample buffers do not change the selected mode.
    /// HDR display requires iOS 16 or later or macOS. On tvOS, use `PiPHKView`.
    public func setDynamicRangeMode(_ dynamicRangeMode: DynamicRangeMode) {
        guard self.dynamicRangeMode != dynamicRangeMode else {
            return
        }
        self.dynamicRangeMode = dynamicRangeMode
        #if !os(tvOS)
        if #available(iOS 16.0, macOS 12.0, *) {
            let metalLayer = layer as? CAMetalLayer
            switch dynamicRangeMode {
            case .hdr:
                if restoreSDRConfiguration == nil {
                    let pixelFormat = colorPixelFormat
                    let colorSpace = metalLayer?.colorspace
                    let wantsEDR = metalLayer?.wantsExtendedDynamicRangeContent ?? false
                    let metadata = metalLayer?.edrMetadata
                    restoreSDRConfiguration = { [weak self, weak metalLayer] in
                        self?.colorPixelFormat = pixelFormat
                        metalLayer?.colorspace = colorSpace
                        metalLayer?.wantsExtendedDynamicRangeContent = wantsEDR
                        metalLayer?.edrMetadata = metadata
                    }
                }
                colorPixelFormat = .rgba16Float
                // Floating-point EDR drawables carry display-linear values, including HDR highlights above 1.
                outputColorSpace = CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020)
                metalLayer?.colorspace = outputColorSpace
                metalLayer?.wantsExtendedDynamicRangeContent = true
                metalLayer?.edrMetadata = nil
            case .sdr:
                restoreSDRConfiguration?()
                restoreSDRConfiguration = nil
                outputColorSpace = nil
            }
        }
        #endif
    }
}

extension MTHKView: MediaMixerOutput {
    // MARK: MediaMixerOutput
    public func selectTrack(_ id: UInt8?, mediaType: CMFormatDescription.MediaType) async {
        switch mediaType {
        case .audio:
            break
        case .video:
            videoTrackId = id
        default:
            break
        }
    }

    nonisolated public func mixer(_ mixer: MediaMixer, didOutput buffer: AVAudioPCMBuffer, when: AVAudioTime) {
    }

    nonisolated public func mixer(_ mixer: MediaMixer, didOutput sampleBuffer: CMSampleBuffer) {
        Task { @MainActor in
            displayImage = try? sampleBuffer.imageBuffer?.makeCIImage()
            #if os(macOS)
            self.needsDisplay = true
            #else
            self.setNeedsDisplay()
            #endif
        }
    }
}

extension MTHKView: StreamOutput {
    // MARK: HKStreamOutput
    nonisolated public func stream(_ stream: some StreamConvertible, didOutput audio: AVAudioBuffer, when: AVAudioTime) {
    }

    nonisolated public func stream(_ stream: some StreamConvertible, didOutput video: CMSampleBuffer) {
        Task { @MainActor in
            displayImage = try? video.imageBuffer?.makeCIImage()
            #if os(macOS)
            self.needsDisplay = true
            #else
            self.setNeedsDisplay()
            #endif
        }
    }
}

#endif
