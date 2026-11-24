import AudioToolbox
import Foundation
import VideoToolbox

/// OS-reported capabilities, not a successful conversion or streaming-protocol test.
struct CodecSupportReport: Sendable {
    enum Availability: Sendable {
        case listed
        case notListed
        case unknown
    }

    enum Acceleration: Sendable, Equatable {
        case hardware
        case software
        case unspecified
    }

    struct Encoder: Sendable, Identifiable {
        let id: String
        let name: String
        let acceleration: Acceleration
    }

    struct Video: Sendable, Identifiable {
        let id: UInt32
        let name: String
        let encoding: Availability
        let encoders: [Encoder]
        let hardwareDecode: Bool
    }

    struct Audio: Sendable, Identifiable {
        let id: UInt32
        let name: String
        let encoding: Availability
        let decoding: Availability
    }

    struct Failure: Sendable, Identifiable {
        let id: String
        let status: OSStatus
    }

    let video: [Video]
    let audio: [Audio]
    let failures: [Failure]
}

enum CodecSupportCatalog {
    private static let videoNames: [(UInt32, String)] = [
        (fourCC("avc1"), "H.264 / AVC"), (fourCC("hvc1"), "H.265 / HEVC"),
        (fourCC("av01"), "AV1"), (fourCC("vp09"), "VP9"),
        (fourCC("apcn"), "Apple ProRes 422"), (fourCC("ap4h"), "Apple ProRes 4444"),
        (fourCC("jpeg"), "JPEG")
    ]
    private static let audioNames: [(UInt32, String)] = [
        (kAudioFormatMPEG4AAC, "AAC"), (kAudioFormatMPEG4AAC_HE, "HE-AAC"),
        (kAudioFormatMPEG4AAC_HE_V2, "HE-AAC v2"), (kAudioFormatMPEG4AAC_ELD, "AAC-ELD"),
        (kAudioFormatOpus, "Opus"), (kAudioFormatAppleLossless, "Apple Lossless"),
        (kAudioFormatFLAC, "FLAC"), (kAudioFormatMPEGLayer3, "MP3"),
        (kAudioFormatLinearPCM, "Linear PCM"), (kAudioFormatAC3, "AC-3"),
        (kAudioFormatEnhancedAC3, "E-AC-3"), (kAudioFormatULaw, "G.711 µ-law"),
        (kAudioFormatALaw, "G.711 A-law")
    ]

    static func read() -> CodecSupportReport {
        var failures: [CodecSupportReport.Failure] = []
        var list: CFArray?
        let videoStatus = VTCopyVideoEncoderList(nil, &list)
        let records = list as? [[String: Any]] ?? []
        let videoAvailable = videoStatus == noErr && list != nil
        if !videoAvailable {
            failures.append(.init(id: "VTCopyVideoEncoderList", status: videoStatus == noErr ? OSStatus(kAudio_ParamError) : videoStatus))
        }
        let encoderFormats = formatIDs(kAudioFormatProperty_EncodeFormatIDs, failures: &failures)
        let decoderFormats = formatIDs(kAudioFormatProperty_DecodeFormatIDs, failures: &failures)
        let videoTypes = Set(videoNames.map(\.0) + records.compactMap { ($0[kVTVideoEncoderList_CodecType as String] as? NSNumber)?.uint32Value })
        let video = ordered(videoTypes, names: videoNames).map { type in
            let matching = records.filter { ($0[kVTVideoEncoderList_CodecType as String] as? NSNumber)?.uint32Value == type }
            let encoders = matching.map { record in
                let name = record[kVTVideoEncoderList_EncoderName as String] as? String ?? formatCode(type)
                return CodecSupportReport.Encoder(
                    id: record[kVTVideoEncoderList_EncoderID as String] as? String ?? name,
                    name: name,
                    acceleration: (record[kVTVideoEncoderList_IsHardwareAccelerated as String] as? NSNumber).map { $0.boolValue ? .hardware : .software } ?? .unspecified
                )
            }
            return CodecSupportReport.Video(
                id: type,
                name: videoNames.first { $0.0 == type }?.1 ?? matching.first?[kVTVideoEncoderList_CodecName as String] as? String ?? formatCode(type),
                encoding: videoAvailable ? (encoders.isEmpty ? .notListed : .listed) : .unknown,
                encoders: encoders,
                hardwareDecode: VTIsHardwareDecodeSupported(type)
            )
        }
        let audioTypes = Set(audioNames.map(\.0)).union(encoderFormats ?? []).union(decoderFormats ?? [])
        let audio = ordered(audioTypes, names: audioNames).map { type in
            CodecSupportReport.Audio(
                id: type, name: audioNames.first { $0.0 == type }?.1 ?? formatCode(type),
                encoding: availability(type, in: encoderFormats), decoding: availability(type, in: decoderFormats)
            )
        }
        return CodecSupportReport(video: video, audio: audio, failures: failures)
    }

    static func formatCode(_ value: UInt32) -> String {
        let bytes = stride(from: 24, through: 0, by: -8).map { UInt8((value >> $0) & 0xff) }
        guard bytes.allSatisfy({ (32...126).contains($0) }) else {
            return String(format: "0x%08X", value)
        }
        return "‘\(String(bytes: bytes, encoding: .ascii) ?? "")’"
    }

    private static func fourCC(_ string: String) -> UInt32 {
        string.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private static func ordered(_ types: Set<UInt32>, names: [(UInt32, String)]) -> [UInt32] {
        let known = names.map(\.0).filter { types.contains($0) }
        return known + types.subtracting(known).sorted()
    }

    private static func availability(_ type: UInt32, in formats: Set<UInt32>?) -> CodecSupportReport.Availability {
        guard let formats else { return .unknown }
        return formats.contains(type) ? .listed : .notListed
    }

    private static func formatIDs(_ property: AudioFormatPropertyID, failures: inout [CodecSupportReport.Failure]) -> Set<UInt32>? {
        var size: UInt32 = 0
        var status = AudioFormatGetPropertyInfo(property, 0, nil, &size)
        let operation = property == kAudioFormatProperty_EncodeFormatIDs ? "AudioConverter encode formats" : "AudioConverter decode formats"
        guard status == noErr, size.isMultiple(of: UInt32(MemoryLayout<UInt32>.size)) else {
            failures.append(.init(id: operation, status: status == noErr ? OSStatus(kAudio_ParamError) : status))
            return nil
        }
        if size == 0 { return [] }
        let capacity = size
        var values = [UInt32](repeating: 0, count: Int(size) / MemoryLayout<UInt32>.size)
        status = values.withUnsafeMutableBytes { buffer in
            AudioFormatGetProperty(property, 0, nil, &size, buffer.baseAddress!)
        }
        guard status == noErr, size <= capacity, size.isMultiple(of: UInt32(MemoryLayout<UInt32>.size)) else {
            failures.append(.init(id: operation, status: status == noErr ? OSStatus(kAudio_ParamError) : status))
            return nil
        }
        return Set(values.prefix(Int(size) / MemoryLayout<UInt32>.size))
    }
}
