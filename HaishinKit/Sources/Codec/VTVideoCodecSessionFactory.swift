import CoreMedia
import Foundation
import VideoToolbox

struct VTVideoCodecSessionFactory: VideoCodecSessionFactory {
    func supportedFormats(for mode: VideoCodecSessionMode) -> [VideoCodecSettings.Format] {
        [.h264, .hevc]
    }

    func makeSession(mode: VideoCodecSessionMode, settings: VideoCodecSettings, inputFormat: CMFormatDescription) throws -> any VideoCodecSession {
        let session = try (mode == .compression ? VTSessionMode.compression : .decompression).makeSession(settings: settings, inputFormat: inputFormat)
        return Session(session: session, settings: settings, mode: mode)
    }

    private final class Session: VideoCodecSession {
        private var session: (any VTSessionConvertible)?
        private var settings: VideoCodecSettings
        private let mode: VideoCodecSessionMode

        init(session: any VTSessionConvertible, settings: VideoCodecSettings, mode: VideoCodecSessionMode) {
            self.session = session
            self.settings = settings
            self.mode = mode
        }

        deinit {
            invalidate()
        }

        func convert(_ sampleBuffer: CMSampleBuffer, continuation: AsyncStream<CMSampleBuffer>.Continuation?) throws {
            guard let session else { throw VTSessionError.failedToConvert(status: kVTInvalidSessionErr) }
            try session.convert(sampleBuffer, continuation: continuation)
        }

        func update(_ settings: VideoCodecSettings) throws {
            guard let session else { throw VTSessionError.failedToPrepare(status: kVTInvalidSessionErr) }
            guard mode == .compression else { return }
            if settings.bitRate != self.settings.bitRate {
                let status = session.setOption(.init(key: settings.bitRateMode.key, value: NSNumber(value: settings.bitRate)))
                guard status == noErr else { throw VTSessionError.failedToPrepare(status: status) }
            }
            if settings.expectedFrameRate != self.settings.expectedFrameRate {
                let status = session.setOption(.init(key: .expectedFrameRate, value: NSNumber(value: settings.expectedFrameRate ?? 0)))
                guard status == noErr else { throw VTSessionError.failedToPrepare(status: status) }
            }
            self.settings = settings
        }

        func invalidate() {
            session?.invalidate()
            session = nil
        }
    }
}
