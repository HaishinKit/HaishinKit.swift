import Foundation
import HaishinKit
import libdatachannel

struct RTCTrackConfiguration: Sendable {
    private static func generateSSRC() -> UInt32 {
        var ssrc: UInt32 = 0
        repeat {
            ssrc = UInt32.random(in: 1...UInt32.max)
        } while ssrc == 0
        return ssrc
    }

    private static func generateCName() -> String {
        return String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16))
    }

    let codec: rtcCodec
    let ssrc: UInt32
    let pt: Int32
    let mid: String
    let name: String
    let msid: String
    let trackId: String
    let profile: String?
}

extension RTCTrackConfiguration {
    init(mid: String, streamId: String, audioCodecSettings: AudioCodecSettings) {
        self.codec = audioCodecSettings.format.cValue ?? RTC_CODEC_OPUS
        self.ssrc = Self.generateSSRC()
        self.pt = 111
        self.mid = mid
        self.name = Self.generateCName()
        self.msid = streamId
        self.trackId = UUID().uuidString
        self.profile = "minptime=10;useinbandfec=1;stereo=1;sprop-stereo=1"
    }

    init(mid: String, streamId: String, videoCodecSettings: VideoCodecSettings) {
        self.codec = videoCodecSettings.format.cValue
        self.ssrc = Self.generateSSRC()
        self.pt = 98
        self.mid = mid
        self.name = Self.generateCName()
        self.msid = streamId
        self.trackId = UUID().uuidString
        self.profile = nil
    }
}

extension RTCTrackConfiguration {
    func addTrack(_ connection: Int32, direction: RTCDirection) throws -> Int32 {
        let strings = [mid, name, msid, trackId, profile ?? ""]
        return try RTCError.check(strings.withCStrings { pointers in
            var config = rtcTrackInit(
                direction: direction.cValue,
                codec: codec,
                payloadType: pt,
                ssrc: ssrc,
                mid: pointers[0],
                name: pointers[1],
                msid: pointers[2],
                trackId: pointers[3],
                profile: profile == nil ? nil : pointers[4]
            )
            return rtcAddTrackEx(connection, &config)
        })
    }
}
