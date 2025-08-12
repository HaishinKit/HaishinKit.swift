import AVFoundation
import Foundation

/// Configuration calback block for IOVideoCaptureUnit.
@available(tvOS 17.0, *)
public typealias IOVideoCaptureConfigurationBlock = (IOVideoCaptureUnit?, IOVideoUnitError?) -> Void

/// An object that provides the interface to control the AVCaptureDevice's transport behavior.
@available(tvOS 17.0, *)
public final class IOVideoCaptureUnit: IOCaptureUnit {
    public typealias Output = AVCaptureVideoDataOutput

    /// The default color format.
    public static let colorFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange

    /// The current video device object.
    public private(set) var device: AVCaptureDevice?

    /// Specifies the video capture color format.
    public var colorFormat = IOVideoCaptureUnit.colorFormat

    /// The track number.
    public let track: UInt8
    /// The input data to a cupture session.
    public private(set) var input: AVCaptureInput?
    /// The output data to a sample buffers.
    public private(set) var output: Output? {
        didSet {
            oldValue?.setSampleBufferDelegate(nil, queue: nil)
            guard let output else {
                return
            }
            output.alwaysDiscardsLateVideoFrames = true
            #if os(iOS) || os(macOS) || os(tvOS)
            if output.availableVideoPixelFormatTypes.contains(colorFormat) {
                output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: colorFormat)]
            } else {
                logger.warn("device doesn't support this color format ", colorFormat, ".")
            }
            #endif
        }
    }
    /// The connection from a capture input to a capture output.
    public private(set) var connection: AVCaptureConnection?

    #if os(iOS) || os(macOS)
    /// Specifies the videoOrientation indicates whether to rotate the video flowing through the connection to a given orientation.
    public var videoOrientation: AVCaptureVideoOrientation = .portrait {
        didSet {
            output?.connections.filter { $0.isVideoOrientationSupported }.forEach {
                $0.videoOrientation = videoOrientation
            }
        }
    }
    #endif

    #if os(iOS) || os(macOS) || os(tvOS)
    /// Spcifies the video mirroed indicates whether the video flowing through the connection should be mirrored about its vertical axis.
    public var isVideoMirrored = false {
        didSet {
            output?.connections.filter { $0.isVideoMirroringSupported }.forEach {
                $0.isVideoMirrored = isVideoMirrored
            }
        }
    }
    #endif

    #if os(iOS)
    /// Specifies the preferredVideoStabilizationMode most appropriate for use with the connection.
    public var preferredVideoStabilizationMode: AVCaptureVideoStabilizationMode = .off {
        didSet {
            output?.connections.filter { $0.isVideoStabilizationSupported }.forEach {
                $0.preferredVideoStabilizationMode = preferredVideoStabilizationMode
            }
        }
    }
    #endif

    private var dataOutput: IOVideoCaptureUnitDataOutput?

    init(_ track: UInt8) {
        self.track = track
    }

    func attachDevice(_ device: AVCaptureDevice?, videoUnit: IOVideoUnit) throws {
        setSampleBufferDelegate(nil)
        videoUnit.mixer?.session.detachCapture(self)
        guard let device else {
            self.device = nil
            input = nil
            output = nil
            connection = nil
            return
        }
        self.device = device
        input = try AVCaptureDeviceInput(device: device)
        output = AVCaptureVideoDataOutput()
        #if os(iOS)
        if let output, let port = input?.ports.first(where: { $0.mediaType == .video && $0.sourceDeviceType == device.deviceType && $0.sourceDevicePosition == device.position }) {
            connection = AVCaptureConnection(inputPorts: [port], output: output)
        } else {
            connection = nil
        }
        #elseif os(tvOS) || os(macOS)
        if let output, let port = input?.ports.first(where: { $0.mediaType == .video }) {
            connection = AVCaptureConnection(inputPorts: [port], output: output)
        } else {
            connection = nil
        }
        #endif
        videoUnit.mixer?.session.attachCapture(self)
        #if os(iOS) || os(tvOS) || os(macOS)
        output?.connections.forEach {
            if $0.isVideoMirroringSupported {
                $0.isVideoMirrored = isVideoMirrored
            }
            #if os(iOS) || os(macOS)
            if $0.isVideoOrientationSupported {
                $0.videoOrientation = videoOrientation
            }
            #endif
            #if os(iOS)
            if $0.isVideoStabilizationSupported {
                $0.preferredVideoStabilizationMode = preferredVideoStabilizationMode
            }
            #endif
        }
        #endif
        setSampleBufferDelegate(videoUnit)
    }

    func setFrameRate(_ frameRate: Float64) {
        guard let device else {
            return
        }
        do {
            try device.lockForConfiguration()
            if device.activeFormat.isFrameRateSupported(frameRate) {
                device.activeVideoMinFrameDuration = CMTime(value: 100, timescale: CMTimeScale(100 * frameRate))
                device.activeVideoMaxFrameDuration = CMTime(value: 100, timescale: CMTimeScale(100 * frameRate))
            } else {
                if let format = device.videoFormat(
                    width: device.activeFormat.formatDescription.dimensions.width,
                    height: device.activeFormat.formatDescription.dimensions.height,
                    frameRate: frameRate,
                    isMultiCamSupported: device.activeFormat.isMultiCamSupported
                ) {
                    device.activeFormat = format
                    device.activeVideoMinFrameDuration = CMTime(value: 100, timescale: CMTimeScale(100 * frameRate))
                    device.activeVideoMaxFrameDuration = CMTime(value: 100, timescale: CMTimeScale(100 * frameRate))
                }
            }
            device.unlockForConfiguration()
        } catch {
            logger.error("while locking device for fps:", error)
        }
    }

    #if os(iOS) || os(tvOS) || os(macOS)
    func setTorchMode(_ torchMode: AVCaptureDevice.TorchMode) {
        guard let device, device.isTorchModeSupported(torchMode) else {
            return
        }
        do {
            try device.lockForConfiguration()
            device.torchMode = torchMode
            device.unlockForConfiguration()
        } catch {
            logger.error("while setting torch:", error)
        }
    }
    #endif

    func setSampleBufferDelegate(_ videoUnit: IOVideoUnit?) {
        if let videoUnit {
            #if os(iOS) || os(macOS)
            videoOrientation = videoUnit.videoOrientation
            #endif
            setFrameRate(videoUnit.frameRate)
        }
        dataOutput = videoUnit?.makeDataOutput(track)
        output?.setSampleBufferDelegate(dataOutput, queue: videoUnit?.lockQueue)
    }
}

@available(tvOS 17.0, *)
final class IOVideoCaptureUnitDataOutput: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let track: UInt8
    private let videoMixer: IOVideoMixer<IOVideoUnit>

    init(track: UInt8, videoMixer: IOVideoMixer<IOVideoUnit>) {
        self.track = track
        self.videoMixer = videoMixer
    }

    func captureOutput(_ captureOutput: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        videoMixer.append(track, sampleBuffer: sampleBuffer)
    }
}
