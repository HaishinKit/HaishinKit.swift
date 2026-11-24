import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS) || os(visionOS)
import UIKit
#endif

/// Shared by all four sample applications; only public OS capability queries are used.
struct CodecSupportView: View {
    var showsDismissButton = true
    @Environment(\.dismiss) private var dismiss
    @State private var report: CodecSupportReport?
    @State private var audio = false
    @State private var reload = 0
    @State private var isReading = false
    @State private var copied = false
    @State private var copyFailed = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(localized("Device codecs")).font(.title2.bold())
                Spacer()
                if showsDismissButton {
                    Button(localized("Done")) { dismiss() }
                }
            }.padding()
            HStack {
                Picker(localized("Media type"), selection: $audio) {
                    Text(localized("Video")).tag(false)
                    Text(localized("Audio")).tag(true)
                }.pickerStyle(.segmented)
                #if !os(tvOS)
                Button { copyReport() } label: {
                    Label(localized(copied ? "Copied" : "Copy"), systemImage: copied ? "checkmark" : "doc.on.doc")
                }.disabled(report == nil || isReading)
                #endif
            }.padding(.horizontal)
            if copyFailed {
                Text(localized("Could not copy the report.")).foregroundStyle(.secondary)
            }
            if let report {
                List {
                    Section {
                        Text(localized("Device reports are not a guarantee of app, protocol, profile or resolution support."))
                        Text(localized(audio
                            ? "AudioConverter lists input and output formats. Actual AVAudioConverter conversions depend on the format pair and audio settings; they are not tested here."
                            : "VideoToolbox lists encoders. Hardware decoding is checked for selected common formats and encoder-listed formats only. Software decoding is not tested; other formats may still play."))
                            .foregroundStyle(.secondary)
                    }
                    #if targetEnvironment(simulator)
                    Text(localized("Simulator results do not describe a physical device.")).foregroundStyle(.secondary)
                    #endif
                    if audio {
                        ForEach(report.audio) { codec in
                            CodecSupportRow(name: codec.name, code: codec.id, values: [
                                (localized("Encode"), availability(codec.encoding)),
                                (localized("Decode"), availability(codec.decoding))
                            ], details: [])
                        }
                    } else {
                        ForEach(report.video) { codec in
                            CodecSupportRow(name: codec.name, code: codec.id, values: [
                                (localized("Encode"), encoderAvailability(codec)),
                                (localized("Hardware decode"), localized(codec.hardwareDecode ? "Available" : "Not reported"))
                            ], details: codec.encoders.map { encoder in
                                let kind: String
                                switch encoder.acceleration {
                                case .hardware: kind = localized("Hardware")
                                case .software: kind = localized("Software")
                                case .unspecified: kind = localized("Unspecified")
                                }
                                return "\(encoder.name) · \(kind)\n\(encoder.id)"
                            })
                        }
                    }
                    if !report.failures.isEmpty {
                        Section(localized("Query errors")) {
                            ForEach(report.failures) { failure in
                                Text("\(failure.id): \(failure.status)").font(.caption)
                            }
                        }
                    }
                    Section {
                        Button(localized("Refresh")) {
                            isReading = true
                            reload += 1
                        }.disabled(isReading)
                        #if os(tvOS)
                        Text(localized("tvOS does not provide a public clipboard API.")).foregroundStyle(.secondary)
                        #endif
                        #if !os(tvOS)
                        Link(localized("AVAudioConverter documentation"), destination: URL(string: "https://developer.apple.com/documentation/avfaudio/avaudioconverter")!)
                        #endif
                    }
                }
            } else {
                Spacer()
                ProgressView(localized("Reading device codecs…"))
                Spacer()
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, idealWidth: 680, minHeight: 450, idealHeight: 650)
        #elseif os(visionOS)
        .frame(minWidth: 500, idealWidth: 680, minHeight: 450, idealHeight: 650)
        #endif
        #if os(tvOS)
        .onExitCommand { dismiss() }
        #endif
        .task(id: reload) {
            isReading = true
            let value = await Task.detached(priority: .utility) { CodecSupportCatalog.read() }.value
            guard !Task.isCancelled else { return }
            report = value
            isReading = false
            copied = false
            copyFailed = false
        }
    }

    #if !os(tvOS)
    private func copyReport() {
        guard let report else { return }
        #if os(macOS)
        let platform = "macOS"
        #elseif os(iOS)
        let platform = "iOS"
        #elseif os(visionOS)
        let platform = "visionOS"
        #else
        let platform = "tvOS"
        #endif
        #if targetEnvironment(simulator)
        let simulated = true
        #else
        let simulated = false
        #endif
        let text = report.textReport(platform: platform, osVersion: ProcessInfo.processInfo.operatingSystemVersionString, simulated: simulated)
        #if os(macOS)
        NSPasteboard.general.clearContents()
        copied = NSPasteboard.general.setString(text, forType: .string)
        copyFailed = !copied
        #elseif os(iOS) || os(visionOS)
        UIPasteboard.general.string = text
        copied = true
        copyFailed = false
        #endif
    }

    #endif

    private func availability(_ value: CodecSupportReport.Availability) -> String {
        switch value {
        case .listed: return localized("Listed")
        case .notListed: return localized("Not listed")
        case .unknown: return localized("Unknown")
        }
    }

    private func encoderAvailability(_ codec: CodecSupportReport.Video) -> String {
        guard case .listed = codec.encoding else { return availability(codec.encoding) }
        let hardware = codec.encoders.contains { $0.acceleration == .hardware }
        let software = codec.encoders.contains { $0.acceleration == .software }
        if hardware && software { return localized("Hardware + software") }
        if hardware { return localized("Hardware") }
        if software { return localized("Software") }
        return localized("Listed")
    }
}

private struct CodecSupportRow: View {
    let name: String
    let code: UInt32
    let values: [(String, String)]
    let details: [String]
    @State private var expanded = false

    var body: some View {
        Section(name) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(values.indices, id: \.self) { index in
                    HStack(alignment: .top) {
                        Text(values[index].0)
                        Spacer(minLength: 16)
                        Text(values[index].1).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                    }
                }
            }
            Button(localized(expanded ? "Hide details" : "Codec details")) { expanded.toggle() }
            if expanded {
                Text(CodecSupportCatalog.formatCode(code)).font(.caption.monospaced())
                ForEach(details.indices, id: \.self) { index in
                    Text(details[index]).font(.caption).textSelectionIfAvailable()
                }
            }
        }
    }
}

private func localized(_ key: String) -> String {
    String(localized: String.LocalizationValue(key), table: "CodecSupport")
}

private extension View {
    @ViewBuilder
    func textSelectionIfAvailable() -> some View {
        #if os(tvOS)
        self
        #else
        self.textSelection(.enabled)
        #endif
    }
}
