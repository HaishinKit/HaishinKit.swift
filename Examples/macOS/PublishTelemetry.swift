import HaishinKit
import SwiftUI
import VideoToolbox

enum OutputResolution: String, CaseIterable, Identifiable {
    case sd480 = "854 × 480"
    case hd720 = "1280 × 720"
    case hd1080 = "1920 × 1080"
    var id: Self { self }
    var size: CGSize {
        switch self {
        case .sd480: return CGSize(width: 854, height: 480)
        case .hd720: return CGSize(width: 1280, height: 720)
        case .hd1080: return CGSize(width: 1920, height: 1080)
        }
    }
}

enum OutputVideoCodec: String, CaseIterable, Identifiable {
    case h264 = "H.264"
    case hevc = "HEVC"
    var id: Self { self }
    var profileLevel: String {
        switch self {
        case .h264: return kVTProfileLevel_H264_Main_AutoLevel as String
        case .hevc: return kVTProfileLevel_HEVC_Main_AutoLevel as String
        }
    }
}

/// Observes network reports without changing the user's encoder settings.
actor PublishTelemetry: StreamBitRateStrategy {
    nonisolated let mamimumVideoBitRate = 0
    nonisolated let mamimumAudioBitRate = 0
    private(set) var report: NetworkMonitorReport?

    func adjustBitrate(_ event: NetworkMonitorEvent, stream: some StreamConvertible) async {
        switch event {
        case .status(let report), .publishInsufficientBWOccured(let report): self.report = report
        case .reset: report = nil
        }
    }
}

struct PublishMetricsPanel: View {
    @ObservedObject var model: PublishViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 24) { metrics }
                VStack(alignment: .leading, spacing: 12) { metrics }
            }
            Text(model.activeEncodingDescription ?? String(localized: "Encoder settings below apply when you start publishing."))
                .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder private var metrics: some View {
        metric(String(localized: "Measured TX"), model.networkReport.map { "\($0.currentBytesOutPerSecond * 8 / 1000) kbps" } ?? "—")
        metric(String(localized: "Target video"), "\(model.videoBitRate / 1000) kbps")
        metric(String(localized: "Output FPS"), model.measuredFPS.map { String($0) } ?? "—")
        metric(String(localized: "Send queue"), model.networkReport.map { "\($0.currentQueueBytesOut / 1024) KB" } ?? "—")
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(.body, design: .monospaced).weight(.medium))
        }
    }
}
