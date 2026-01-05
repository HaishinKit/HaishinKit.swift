import Combine
import HaishinKit
import SwiftUI

enum ViewType: String, CaseIterable, Identifiable {
    case metal
    case pip

    var id: Self { self }

    var displayName: String {
        switch self {
        case .metal: return "Metal"
        case .pip: return "System PiP"
        }
    }
}

enum AudioSourceServiceMode: String, CaseIterable, Sendable {
    case audioSource
    case audioSourceWithStereo
    case audioEngine
}

@MainActor
final class PreferenceViewModel: ObservableObject {
    private enum Keys {
        static let uri = "pref_stream_uri"
        static let streamName = "pref_stream_name"
        static let audioFormat = "pref_audio_format"
        static let bitRateMode = "pref_bitrate_mode"
        static let isLowLatencyEnabled = "pref_low_latency"
        static let viewType = "pref_view_type"
        static let isGPURendererEnabled = "pref_gpu_renderer"
        static let audioCaptureMode = "pref_audio_capture_mode"
        static let isDualCameraEnabled = "pref_dual_camera"
        static let isHDREnabled = "pref_hdr_enabled"
    }

    @Published var showPublishSheet: Bool = false

    @Published var uri: String {
        didSet {
            UserDefaults.standard.set(uri, forKey: Keys.uri)
        }
    }
    @Published var streamName: String {
        didSet {
            UserDefaults.standard.set(streamName, forKey: Keys.streamName)
        }
    }

    private(set) var bitRateModes: [VideoCodecSettings.BitRateMode] = [.average]

    // MARK: - AudioCodecSettings.
    @Published var audioFormat: AudioCodecSettings.Format = .aac {
        didSet {
            UserDefaults.standard.set(audioFormat.rawValue, forKey: Keys.audioFormat)
        }
    }

    // MARK: - VideoCodecSettings.
    @Published var bitRateMode: VideoCodecSettings.BitRateMode = .average {
        didSet {
            UserDefaults.standard.set(bitRateMode.description, forKey: Keys.bitRateMode)
        }
    }
    @Published var isLowLatencyRateControlEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isLowLatencyRateControlEnabled, forKey: Keys.isLowLatencyEnabled)
        }
    }

    // MARK: - Others
    @Published var viewType: ViewType = .metal {
        didSet {
            UserDefaults.standard.set(viewType.rawValue, forKey: Keys.viewType)
        }
    }
    @Published var isGPURendererEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isGPURendererEnabled, forKey: Keys.isGPURendererEnabled)
        }
    }
    @Published var audioCaptureMode: AudioSourceServiceMode = .audioEngine {
        didSet {
            UserDefaults.standard.set(audioCaptureMode.rawValue, forKey: Keys.audioCaptureMode)
        }
    }
    @Published var isDualCameraEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isDualCameraEnabled, forKey: Keys.isDualCameraEnabled)
        }
    }
    @Published var isHDREnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isHDREnabled, forKey: Keys.isHDREnabled)
        }
    }

    init() {
        let defaults = UserDefaults.standard

        self.uri = defaults.string(forKey: Keys.uri) ?? Preference.default.uri
        self.streamName = defaults.string(forKey: Keys.streamName) ?? Preference.default.streamName

        if let rawValue = defaults.string(forKey: Keys.audioFormat),
           let format = AudioCodecSettings.Format(rawValue: rawValue) {
            self.audioFormat = format
        }

        if let savedMode = defaults.string(forKey: Keys.bitRateMode) {
            if savedMode == VideoCodecSettings.BitRateMode.average.description {
                self.bitRateMode = .average
            } else if #available(iOS 16.0, tvOS 16.0, *), savedMode == VideoCodecSettings.BitRateMode.constant.description {
                self.bitRateMode = .constant
            }
        }

        if defaults.object(forKey: Keys.isLowLatencyEnabled) != nil {
            self.isLowLatencyRateControlEnabled = defaults.bool(forKey: Keys.isLowLatencyEnabled)
        }

        if let rawValue = defaults.string(forKey: Keys.viewType),
           let type = ViewType(rawValue: rawValue) {
            self.viewType = type
        }

        if defaults.object(forKey: Keys.isGPURendererEnabled) != nil {
            self.isGPURendererEnabled = defaults.bool(forKey: Keys.isGPURendererEnabled)
        }

        if let rawValue = defaults.string(forKey: Keys.audioCaptureMode),
           let mode = AudioSourceServiceMode(rawValue: rawValue) {
            self.audioCaptureMode = mode
        }

        if defaults.object(forKey: Keys.isDualCameraEnabled) != nil {
            self.isDualCameraEnabled = defaults.bool(forKey: Keys.isDualCameraEnabled)
        }

        if defaults.object(forKey: Keys.isHDREnabled) != nil {
            self.isHDREnabled = defaults.bool(forKey: Keys.isHDREnabled)
        }

        if #available(iOS 16.0, tvOS 16.0, *) {
            bitRateModes.append(.constant)
        }
        if #available(iOS 26.0, tvOS 26.0, macOS 26.0, *) {
            bitRateModes.append(.variable)
        }
    }

    func makeVideoCodecSettings(_ settings: VideoCodecSettings) -> VideoCodecSettings {
        var newSettings = settings
        newSettings.bitRateMode = bitRateMode
        newSettings.isLowLatencyRateControlEnabled = isLowLatencyRateControlEnabled
        return newSettings
    }

    func makeAudioCodecSettings(_ settings: AudioCodecSettings) -> AudioCodecSettings {
        var newSettings = settings
        newSettings.format = audioFormat
        return newSettings
    }

    func makeURL() -> URL? {
        if uri.contains("rtmp://") {
            return URL(string: uri + "/" + streamName)
        }
        return URL(string: uri)
    }
}
