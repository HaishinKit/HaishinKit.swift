import AVFAudio
import CoreMedia
import Foundation
import libdatachannel

protocol RTCTrackDelegate: AnyObject {
    func track(_ track: RTCTrack, readyStateChanged readyState: RTCTrack.ReadyState)
    func track(_ track: RTCTrack, didOutput buffer: CMSampleBuffer)
    func track(_ track: RTCTrack, didOutput buffer: AVAudioCompressedBuffer, when: AVAudioTime)
}

class RTCTrack: RTCChannel {
    enum ReadyState {
        case connecting
        case open
        case closing
        case closed
    }

    let id: Int32
    weak var delegate: (any RTCTrackDelegate)?

    var mid: String {
        do {
            return try CUtil.getString { buffer, size in
                rtcGetTrackMid(id, buffer, size)
            }
        } catch {
            logger.warn(error)
            return ""
        }
    }

    var description: String {
        do {
            return try CUtil.getString { buffer, size in
                rtcGetTrackDescription(id, buffer, size)
            }
        } catch {
            logger.warn(error)
            return ""
        }
    }

    var ssrc: UInt32 {
        do {
            return try CUtil.getUInt32 { buffer, size in
                rtcGetSsrcsForTrack(id, buffer, size)
            }
        } catch {
            logger.warn(error)
            return 0
        }
    }

    private(set) var readyState: ReadyState = .connecting {
        didSet {
            switch readyState {
            case .connecting:
                break
            case .open:
                do {
                    packetizer = try makePacketizer()
                } catch {
                    logger.warn(error)
                }
            case .closing:
                break
            case .closed:
                break
            }
            delegate?.track(self, readyStateChanged: readyState)
        }
    }

    private var packetizer: (any RTPPacketizer)?

    init(id: Int32) throws {
        self.id = id
        try RTCError.check(id)
        do {
            rtcSetUserPointer(id, Unmanaged.passUnretained(self).toOpaque())
            try RTCError.check(rtcSetOpenCallback(id) { _, pointer in
                guard let pointer else { return }
                Unmanaged<RTCTrack>.fromOpaque(pointer).takeUnretainedValue().readyState = .open
            })
            try RTCError.check(rtcSetClosedCallback(id) { _, pointer in
                guard let pointer else { return }
                Unmanaged<RTCTrack>.fromOpaque(pointer).takeUnretainedValue().readyState = .closed
            })
            try RTCError.check(rtcSetMessageCallback(id) { _, bytes, size, pointer in
                guard let bytes, let pointer else { return }
                if 0 <= size {
                    let data = Data(bytes: bytes, count: Int(size))
                    Unmanaged<RTCTrack>.fromOpaque(pointer).takeUnretainedValue().didReceiveMessage(data)
                }
            })
            try RTCError.check(rtcSetErrorCallback(id) { _, error, pointer in
                guard let error, let pointer else { return }
                Unmanaged<RTCTrack>.fromOpaque(pointer).takeUnretainedValue().errorOccurred(String(cString: error))
            })
        } catch {
            rtcDeleteTrack(id)
            throw error
        }
    }

    deinit {
        rtcDeleteTrack(id)
    }

    func send(_ buffer: CMSampleBuffer) {
        packetizer?.append(buffer) { packet in
            try? send(packet.data)
        }
    }

    func send(_ buffer: AVAudioCompressedBuffer, when: AVAudioTime) {
        packetizer?.append(buffer, when: when) { packet in
            try? send(packet.data)
        }
    }

    func didReceiveMessage(_ message: Data) {
        // RTCP shares this callback when RTP/RTCP multiplexing is negotiated.
        guard message.count >= 2, !(192...223).contains(message[1]) else { return }
        do {
            let packet = try RTPPacket(message)
            packetizer?.append(packet)
        } catch {
            logger.warn(error)
        }
    }

    private func errorOccurred(_ error: String) {
        logger.warn(error)
    }

    private func makePacketizer() throws -> (any RTPPacketizer)? {
        let description = try SDPMediaDescription(sdp: description)
        var result: (any RTPPacketizer)?
        let rtpmap = description.attributes.compactMap { attr -> (UInt8, String, Int, Int?)? in
            if case let .rtpmap(payload, codec, clock, channel) = attr { return (payload, codec, clock, channel) }
            return nil
        }
        guard !rtpmap.isEmpty else {
            return nil
        }
        switch rtpmap[0].1.lowercased() {
        case "opus":
            let packetizer = RTPOpusPacketizer<RTCTrack>(ssrc: ssrc, payloadType: description.payload)
            packetizer.delegate = self
            result = packetizer
        case "h264":
            let packetizer = RTPH264Packetizer<RTCTrack>(ssrc: ssrc, payloadType: description.payload)
            packetizer.delegate = self
            result = packetizer
        default:
            break
        }
        for attribute in description.attributes {
            switch attribute {
            case .fmtp(_, let params):
                result?.formatParameter = RTPFormatParameter(params)
            default:
                break
            }
        }
        return result
    }
}

extension RTCTrack: RTPPacketizerDelegate {
    // MARK: RTPPacketizerDelegate
    func packetizer(_ packetizer: some RTPPacketizer, didOutput buffer: CMSampleBuffer) {
        delegate?.track(self, didOutput: buffer)
    }

    func packetizer(_ packetizer: some RTPPacketizer, didOutput buffer: AVAudioCompressedBuffer, when: AVAudioTime) {
        delegate?.track(self, didOutput: buffer, when: when)
    }
}
