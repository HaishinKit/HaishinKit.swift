import SwiftUI

/// Shared by all four sample applications; only public OS capability queries are used.
struct CodecSupportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var report: CodecSupportReport?
    @State private var audio = false
    @State private var reload = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(localized("Device codecs")).font(.title2.bold())
                Spacer()
                Button(localized("Done")) { dismiss() }
            }.padding()
            Picker(localized("Media type"), selection: $audio) {
                Text(localized("Video")).tag(false)
                Text(localized("Audio")).tag(true)
            }.pickerStyle(.segmented).padding(.horizontal)
            if let report {
                List {
                    Section {
                        Text(localized("Device reports are not a guarantee of app, protocol, profile or resolution support."))
                        Text(localized(audio
                            ? "AudioConverter lists input and output formats. Actual AVAudioConverter conversions depend on the format pair and audio settings; they are not tested here."
                            : "VideoToolbox lists encoder implementations and hardware decoding. Software decoding is not tested; no hardware report does not mean the codec cannot play."))
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
                        Button(localized("Refresh")) { reload += 1 }
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
            report = nil
            let value = await Task.detached(priority: .utility) { CodecSupportCatalog.read() }.value
            guard !Task.isCancelled else { return }
            report = value
        }
    }

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
