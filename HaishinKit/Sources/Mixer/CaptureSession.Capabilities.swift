import AVFoundation

extension CaptureSession {
    #if os(macOS)
    struct Capabilities {
        static let isMultiCamSupported = true

        var isMultiCamSessionEnabled = true {
            didSet {
                isMultiCamSessionEnabled = true
            }
        }

        func synchronizationClock(_ session: AVCaptureSession) -> CMClock? {
            if #available(macOS 12.3, *) {
                return session.synchronizationClock
            } else {
                return session.masterClock
            }
        }

        func makeSession(_ sessionPreset: AVCaptureSession.Preset) -> AVCaptureSession {
            let session = AVCaptureSession()
            if session.canSetSessionPreset(sessionPreset) {
                session.sessionPreset = sessionPreset
            }
            return session
        }

        func isMultitaskingCameraAccessEnabled(_ session: AVCaptureSession) -> Bool {
            false
        }
    }
    #elseif os(iOS) || os(tvOS)
    struct Capabilities {
        static var isMultiCamSupported: Bool {
            if #available(tvOS 17.0, *) {
                return AVCaptureMultiCamSession.isMultiCamSupported
            } else {
                return false
            }
        }

        var isMultiCamSessionEnabled = false {
            didSet {
                if !Self.isMultiCamSupported {
                    isMultiCamSessionEnabled = false
                    logger.info("This device can't support the AVCaptureMultiCamSession.")
                }
            }
        }

        #if os(iOS)
        func synchronizationClock(_ session: AVCaptureSession) -> CMClock? {
            if #available(iOS 15.4, *) {
                return session.synchronizationClock
            } else {
                return session.masterClock
            }
        }
        #endif

        @available(tvOS 17.0, *)
        func isMultitaskingCameraAccessEnabled(_ session: AVCaptureSession) -> Bool {
            if #available(iOS 16.0, tvOS 17.0, *) {
                session.isMultitaskingCameraAccessEnabled
            } else {
                false
            }
        }

        @available(tvOS 17.0, *)
        func makeSession(_ sessionPreset: AVCaptureSession.Preset) -> AVCaptureSession {
            let session: AVCaptureSession
            if isMultiCamSessionEnabled {
                session = AVCaptureMultiCamSession()
            } else {
                session = AVCaptureSession()
            }
            if session.canSetSessionPreset(sessionPreset) {
                session.sessionPreset = sessionPreset
            }
            return session
        }
    }
    #else
    struct Capabilities {
        static let isMultiCamSupported = false

        var isMultiCamSessionEnabled = false {
            didSet {
                isMultiCamSessionEnabled = false
            }
        }

        func synchronizationClock(_ session: AVCaptureSession) -> CMClock? {
            return session.synchronizationClock
        }

        func isMultitaskingCameraAccessEnabled(_ session: AVCaptureSession) -> Bool {
            false
        }
    }
    #endif
}
