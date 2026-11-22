import AVFoundation
import CoreImage

#if !os(visionOS)
/// An object that manages offscreen rendering an asset resource.
public final class AssetScreenObject: ScreenObject, ChromaKeyProcessable {
    override public class var type: String { "asset" }

    private var sourceURL: URL?

    override public var elements: [String: String] {
        get {
            ["source": sourceURL?.absoluteString ?? "", "looping": String(isLooping), "videoGravity": videoGravity.snapshotValue]
        }
        set {
            isLooping = newValue["looping"] == "true"
            videoGravity = .init(snapshotValue: newValue["videoGravity"] ?? AVLayerVideoGravity.resizeAspect.snapshotValue)
            guard let value = newValue["source"], let url = URL(string: value), !value.isEmpty else {
                sourceURL = nil
                cancelReading()
                return
            }
            do { try startReading(AVURLAsset(url: url)) } catch { logger.warn(error) }
        }
    }
    public var chromaKeyColor: CGColor?

    /// Restarts the asset when its video track reaches the end.
    public var isLooping = false

    /// The reading incidies whether assets reading or not.
    public var isReading: Bool {
        return reader?.status == .reading
    }

    /// The video is displayed within a player layer’s bounds.
    public var videoGravity: AVLayerVideoGravity = .resizeAspect {
        didSet {
            guard videoGravity != oldValue else {
                return
            }
            invalidateLayout()
        }
    }

    private var reader: AVAssetReader? {
        didSet {
            if let oldValue, oldValue.status == .reading {
                oldValue.cancelReading()
            }
        }
    }

    private var sampleBuffer: CMSampleBuffer? {
        didSet {
            guard sampleBuffer != oldValue else {
                return
            }
            if sampleBuffer == nil {
                cancelReading()
                return
            }
            invalidateLayout()
        }
    }

    private var startedAt: CMTime = .zero
    private var videoTrackOutput: AVAssetReaderTrackOutput?
    private var outputSettings = [
        kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA
    ] as [String: Any]

    /// Prepares the asset reader to start reading.
    public func startReading(_ asset: AVAsset) throws {
        sourceURL = (asset as? AVURLAsset)?.url
        reader = try AVAssetReader(asset: asset)
        guard let reader else {
            return
        }
        let videoTrack = asset.tracks(withMediaType: .video).first
        if let videoTrack {
            let videoTrackOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: outputSettings)
            videoTrackOutput.alwaysCopiesSampleData = false
            reader.add(videoTrackOutput)
            self.videoTrackOutput = videoTrackOutput
        }
        startedAt = CMClock.hostTimeClock.time
        reader.startReading()
        sampleBuffer = videoTrackOutput?.copyNextSampleBuffer()
    }

    /// Cancels and stops the reader's output.
    public func cancelReading() {
        reader = nil
        sampleBuffer = nil
        videoTrackOutput = nil
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

    override public func makeImage(_ renderer: some ScreenRenderer) -> CIImage? {
        guard let sampleBuffer, let pixelBuffer = sampleBuffer.imageBuffer else {
            return nil
        }
        return CIImage(cvPixelBuffer: pixelBuffer).transformed(by: videoGravity.scale(
            bounds.size,
            image: pixelBuffer.size
        ))
    }

    override func draw(_ renderer: some ScreenRenderer) {
        super.draw(renderer)
        let duration = CMClock.hostTimeClock.time - startedAt
        if let sampleBuffer, sampleBuffer.presentationTimeStamp <= duration {
            if let next = videoTrackOutput?.copyNextSampleBuffer() {
                self.sampleBuffer = next
            } else if isLooping, let reader, reader.status == .completed {
                do {
                    try startReading(reader.asset)
                } catch {
                    cancelReading()
                }
            } else {
                self.sampleBuffer = nil
            }
        }
    }
}
#endif
