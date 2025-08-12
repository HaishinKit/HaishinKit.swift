import AVFoundation
import Combine
import HaishinKit
import Logboard
import PhotosUI
import SwiftUI
import VideoToolbox

final class ViewModel: ObservableObject {
    let maxRetryCount: Int = 5

    private var rtmpConnection = RTMPConnection()
    @Published var rtmpStream: RTMPStream!
    private var sharedObject: RTMPSharedObject!
    private var currentEffect: VideoEffect?
    @Published var currentPosition: AVCaptureDevice.Position = .back
    private var retryCount: Int = 0
    @Published var published = false
    @Published var zoomLevel: CGFloat = 1.0
    @Published var videoRate = CGFloat(VideoCodecSettings.default.bitRate / 1000)
    @Published var audioRate = CGFloat(AudioCodecSettings.default.bitRate / 1000)
    @Published var fps: String = "FPS"
    private var nc = NotificationCenter.default

    var subscriptions = Set<AnyCancellable>()

    var frameRate: String = "30.0" {
        willSet {
            rtmpStream.frameRate = Float64(newValue) ?? 30.0
            objectWillChange.send()
        }
    }

    var videoEffect: String = "None" {
        willSet {
            if let currentEffect: VideoEffect = currentEffect {
                _ = rtmpStream.unregisterVideoEffect(currentEffect)
            }

            switch newValue {
            case "Monochrome":
                currentEffect = MonochromeEffect()
                _ = rtmpStream.registerVideoEffect(currentEffect!)

            case "Pronoma":
                print("case Pronoma")
                currentEffect = PronamaEffect()
                _ = rtmpStream.registerVideoEffect(currentEffect!)

            default:
                break
            }

            objectWillChange.send()
        }
    }

    var videoEffectData = ["None", "Monochrome", "Pronoma"]

    var frameRateData = ["15.0", "30.0", "60.0"]

    func config() {
        rtmpStream = RTMPStream(connection: rtmpConnection)
        rtmpStream.videoMixerSettings.mode = .offscreen
        rtmpStream.screen.startRunning()
        if let orientation = DeviceUtil.videoOrientation(by: UIDevice.current.orientation) {
            rtmpStream.videoOrientation = orientation
        }
        rtmpStream.sessionPreset = .hd1280x720
        rtmpStream.videoSettings.videoSize = .init(width: 1280, height: 720)
        nc.publisher(for: UIDevice.orientationDidChangeNotification, object: nil)
            .sink { [weak self] _ in
                guard let orientation = DeviceUtil.videoOrientation(by: UIDevice.current.orientation), let self = self else {
                    return
                }
                self.rtmpStream.videoOrientation = orientation
            }
            .store(in: &subscriptions)

        checkDeviceAuthorization()
    }

    func checkDeviceAuthorization() {
        let requiredAccessLevel: PHAccessLevel = .readWrite
        PHPhotoLibrary.requestAuthorization(for: requiredAccessLevel) { authorizationStatus in
            switch authorizationStatus {
            case .limited:
                logger.info("limited authorization granted")
            case .authorized:
                logger.info("authorization granted")
            default:
                logger.info("Unimplemented")
            }
        }
    }

    func registerForPublishEvent() {
        rtmpStream.attachAudio(AVCaptureDevice.default(for: .audio)) { _, error in
            if let error {
                logger.error(error)
            }
        }
        rtmpStream.attachCamera(AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: currentPosition)) { _, error  in
            if let error {
                logger.error(error)
            }
        }
        rtmpStream.publisher(for: \.currentFPS)
            .sink { [weak self] currentFPS in
                guard let self = self else {
                    return
                }
                DispatchQueue.main.async {
                    self.fps = self.published == true ? "\(currentFPS)" : "FPS"
                }
            }
            .store(in: &subscriptions)

        nc.publisher(for: AVAudioSession.interruptionNotification, object: nil)
            .sink { notification in
                logger.info(notification)
            }
            .store(in: &subscriptions)

        nc.publisher(for: AVAudioSession.routeChangeNotification, object: nil)
            .sink { notification in
                logger.info(notification)
            }
            .store(in: &subscriptions)
    }

    func unregisterForPublishEvent() {
        rtmpStream.close()
    }

    func startPublish() {
        UIApplication.shared.isIdleTimerDisabled = true
        logger.info(Preference.default.uri!)

        rtmpConnection.addEventListener(.rtmpStatus, selector: #selector(rtmpStatusHandler), observer: self)
        rtmpConnection.addEventListener(.ioError, selector: #selector(rtmpErrorHandler), observer: self)
        rtmpConnection.connect(Preference.default.uri!)
    }

    func stopPublish() {
        UIApplication.shared.isIdleTimerDisabled = false
        rtmpConnection.close()
        rtmpConnection.removeEventListener(.rtmpStatus, selector: #selector(rtmpStatusHandler), observer: self)
        rtmpConnection.removeEventListener(.ioError, selector: #selector(rtmpErrorHandler), observer: self)
    }

    func toggleTorch() {
        rtmpStream.torch.toggle()
    }

    func pausePublish() {
        rtmpStream.paused.toggle()
    }

    func tapScreen(touchPoint: CGPoint) {
        let pointOfInterest = CGPoint(x: touchPoint.x / UIScreen.main.bounds.size.width, y: touchPoint.y / UIScreen.main.bounds.size.height)
        logger.info("pointOfInterest: \(pointOfInterest)")
        guard
            let device = rtmpStream.videoCapture(for: 0)?.device, device.isFocusPointOfInterestSupported else {
            return
        }
        do {
            try device.lockForConfiguration()
            device.focusPointOfInterest = pointOfInterest
            device.focusMode = .continuousAutoFocus
            device.unlockForConfiguration()
        } catch let error as NSError {
            logger.error("while locking device for focusPointOfInterest: \(error)")
        }
    }

    func rotateCamera() {
        let position: AVCaptureDevice.Position = currentPosition == .back ? .front : .back
        rtmpStream.attachCamera(AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)) { _, error  in
            logger.error(error)
        }
        currentPosition = position
    }

    func changeZoomLevel(level: CGFloat) {
        guard let device = rtmpStream.videoCapture(for: 0)?.device, 1 <= level && level < device.activeFormat.videoMaxZoomFactor else {
            return
        }
        do {
            try device.lockForConfiguration()
            device.ramp(toVideoZoomFactor: level, withRate: 5.0)
            device.unlockForConfiguration()
        } catch let error as NSError {
            logger.error("while locking device for ramp: \(error)")
        }
    }

    func changeVideoRate(level: CGFloat) {
        rtmpStream.videoSettings.bitRate = Int(level * 1000)
    }

    func changeAudioRate(level: CGFloat) {
        rtmpStream.audioSettings.bitRate = Int(level * 1000)
    }

    @objc
    private func rtmpStatusHandler(_ notification: Notification) {
        let e = Event.from(notification)
        guard let data: ASObject = e.data as? ASObject, let code: String = data["code"] as? String else {
            return
        }
        print(code)
        switch code {
        case RTMPConnection.Code.connectSuccess.rawValue:
            retryCount = 0
            rtmpStream.publish(Preference.default.streamName!)
        // sharedObject!.connect(rtmpConnection)
        case RTMPConnection.Code.connectFailed.rawValue, RTMPConnection.Code.connectClosed.rawValue:
            guard retryCount <= maxRetryCount else {
                return
            }
            Thread.sleep(forTimeInterval: pow(2.0, Double(retryCount)))
            rtmpConnection.connect(Preference.default.uri!)
            retryCount += 1
        default:
            break
        }
    }

    @objc
    private func rtmpErrorHandler(_ notification: Notification) {
        logger.error(notification)
        rtmpConnection.connect(Preference.default.uri!)
    }
}

extension ViewModel: IOStreamRecorderDelegate {
    // MARK: IOStreamRecorderDelegate
    func recorder(_ recorder: IOStreamRecorder, errorOccured error: IOStreamRecorder.Error) {
        logger.error(error)
    }

    func recorder(_ recorder: IOStreamRecorder, finishWriting writer: AVAssetWriter) {
        PHPhotoLibrary.shared().performChanges({() in
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: writer.outputURL)
        }, completionHandler: { _, error in
            do {
                try FileManager.default.removeItem(at: writer.outputURL)
            } catch {
                print(error)
            }
        })
    }
}
