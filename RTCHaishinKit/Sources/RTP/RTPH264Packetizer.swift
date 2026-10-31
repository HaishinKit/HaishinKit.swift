import AVFAudio
import CoreMedia
import Foundation
import HaishinKit

private let RTPH264Packetizer_startCode = Data([0x00, 0x00, 0x00, 0x01])

/// https://datatracker.ietf.org/doc/html/rfc3984
final class RTPH264Packetizer<T: RTPPacketizerDelegate>: RTPPacketizer {
    let ssrc: UInt32
    let payloadType: UInt8
    weak var delegate: T?
    var formatParameter = RTPFormatParameter()
    private var sequenceNumber: UInt16 = 0
    private var buffer = Data()
    private var nalUnitReader = NALUnitReader()
    private var pictureParameterSets: Data?
    private var sequenceParameterSets: Data?
    private var formatDescription: CMFormatDescription?

    // for FragmentUnitA
    private var fragmentedBuffer = Data()
    private var fragmentedStarted = false
    private var fragmentedTimestamp: UInt32 = 0
    private var timestamp: RTPTimestamp = .init(90000)

    private lazy var jitterBuffer: RTPJitterBuffer<RTPH264Packetizer> = {
        let jitterBuffer = RTPJitterBuffer<RTPH264Packetizer>()
        jitterBuffer.delegate = self
        return jitterBuffer
    }()

    init(ssrc: UInt32, payloadType: UInt8) {
        self.ssrc = ssrc
        self.payloadType = payloadType
    }

    func append(_ packet: RTPPacket) {
        jitterBuffer.append(packet)
    }

    func append(_ buffer: CMSampleBuffer, lambda: (RTPPacket) -> Void) {
        let nals = nalUnitReader.read(buffer)
        for i in 0..<nals.count {
            let marker = i == nals.count - 1

            if nals[i].count <= 1200 {
                lambda(.init(
                    version: RTPPacket.version,
                    padding: false,
                    extension: false,
                    cc: 0,
                    marker: marker,
                    payloadType: payloadType,
                    sequenceNumber: sequenceNumber,
                    timestamp: timestamp.convert(buffer.presentationTimeStamp),
                    ssrc: ssrc,
                    payload: nals[i]
                ))
                sequenceNumber &+= 1
            } else {
                // split FragmentUnit A
                let nalHeader = nals[i][0]
                let fuIndicator = (nalHeader & 0xE0) | 28
                let nalType = nalHeader & 0x1F

                var offset = 1
                var first = true
                let length = nals[i].count

                while offset < length {
                    var fuHeader: UInt8 = nalType
                    let fragmentSize = min(1200 - 2, length - offset)
                    if first {
                        fuHeader |= 0x80
                    }
                    if length <= offset + fragmentSize {
                        fuHeader |= 0x40
                    }
                    var payload = Data()
                    payload.append(fuIndicator)
                    payload.append(fuHeader)
                    payload.append(nals[i][offset..<offset + fragmentSize])

                    lambda(RTPPacket(
                        version: RTPPacket.version,
                        padding: false,
                        extension: false,
                        cc: 0,
                        marker: marker && (length <= offset + fragmentSize),
                        payloadType: payloadType,
                        sequenceNumber: sequenceNumber,
                        timestamp: timestamp.convert(buffer.presentationTimeStamp),
                        ssrc: ssrc,
                        payload: payload
                    ))
                    sequenceNumber &+= 1

                    offset += fragmentSize
                    first = false
                }
            }
        }
    }

    func append(_ buffer: AVAudioCompressedBuffer, when: AVAudioTime, lambda: (RTPPacket) -> Void) {
    }

    private func decode(_ packet: RTPPacket) {
        guard !packet.payload.isEmpty else {
            return
        }
        /**
         Table 1.  Summary of NAL unit types and their payload structures

         Type   Packet    Type name                        Section
         ---------------------------------------------------------
         0      undefined                                    -
         1-23   NAL unit  Single NAL unit packet per H.264   5.6
         24     STAP-A    Single-time aggregation packet     5.7.1
         25     STAP-B    Single-time aggregation packet     5.7.1
         26     MTAP16    Multi-time aggregation packet      5.7.2
         27     MTAP24    Multi-time aggregation packet      5.7.2
         28     FU-A      Fragmentation unit                 5.8
         29     FU-B      Fragmentation unit                 5.8
         30-31  undefined                                    -
         **/
        let nalUnitType = packet.payload[0] & 0x1F
        switch nalUnitType {
        case 1...23:
            decodeSingleNALUnit(packet)
        case 24:
            decodeSingleTimeAggregation(packet)
        case 28:
            decodeFragmentUnitA(packet)
        default:
            logger.warn("undefined nal unit type = ", nalUnitType)
        }
    }

    private func decodeSingleNALUnit(_ packet: RTPPacket) {
        appendNALUnit(packet.payload)
        flushIfMarked(packet)
    }

    /// STAP-A (RFC 6184 §5.7.1): one RTP payload aggregating several NAL units,
    /// each prefixed by a 2-byte big-endian size. MediaMTX/Pion delivers SPS+PPS
    /// (and other small NALs) this way — without STAP-A support the decoder never
    /// receives parameter sets, so no frame is ever emitted.
    private func decodeSingleTimeAggregation(_ packet: RTPPacket) {
        let payload = Data(packet.payload)
        var offset = 1
        while offset + 2 <= payload.count {
            let size = Int(payload[offset]) << 8 | Int(payload[offset + 1])
            offset += 2
            guard 0 < size, offset + size <= payload.count else {
                break
            }
            appendNALUnit(payload.subdata(in: offset..<offset + size))
            offset += size
        }
        flushIfMarked(packet)
    }

    private func appendNALUnit(_ nal: Data) {
        guard !nal.isEmpty else {
            return
        }
        let nalUnitType = nal[nal.startIndex] & 0x1F
        switch nalUnitType {
        case 7: // sps
            if sequenceParameterSets == nil {
                sequenceParameterSets = nal
            }
        case 8: // pps
            if pictureParameterSets == nil {
                pictureParameterSets = nal
            }
        default: // idr/non-idr slices and everything else
            buffer.append(RTPH264Packetizer_startCode)
            buffer.append(nal)
        }
        if formatDescription == nil && sequenceParameterSets != nil && pictureParameterSets != nil {
            formatDescription = makeFormatDescription()
        }
    }

    private func flushIfMarked(_ packet: RTPPacket) {
        guard packet.marker else {
            return
        }
        if let sampleBuffer = makeSampleBuffer(&buffer, timestamp: packet.timestamp) {
            delegate?.packetizer(self, didOutput: sampleBuffer)
        }
        buffer.removeAll(keepingCapacity: false)
    }

    private func decodeFragmentUnitA(_ packet: RTPPacket) {
        let indicator = packet.payload[0]
        // S | E | R | Type(original)
        let header = packet.payload[1]

        let start = (header & 0x80) != 0
        let end = (header & 0x40) != 0
        let h264NALUnitType = header & 0x1F

        if fragmentedTimestamp != packet.timestamp, fragmentedStarted {
            // fragmentedBuffer.removeAll(keepingCapacity: false)
            // fragmentedStarted = false
            fragmentedTimestamp = packet.timestamp
        }

        if start {
            fragmentedBuffer.removeAll(keepingCapacity: false)
            fragmentedBuffer.append(RTPH264Packetizer_startCode)
            fragmentedBuffer.append(indicator & 0x60 | indicator & 0x80 | h264NALUnitType)
            fragmentedBuffer.append(packet.payload[2...])
            fragmentedStarted = true
        } else if fragmentedStarted {
            fragmentedBuffer.append(packet.payload[2...])
        }

        if end && fragmentedStarted {
            // A completed FU-A is ONE NAL unit (one slice), not a whole access
            // unit — multi-slice frames (x264 zerolatency uses several slices per
            // frame) span several FU-As. Emitting per-fragment hands VideoToolbox
            // a partial frame → kVTVideoDecoderBadDataErr on every frame. Append
            // to the AU accumulator and emit only at the RTP marker (end of AU),
            // same as the single-NAL and STAP-A paths.
            buffer.append(fragmentedBuffer)
            fragmentedBuffer.removeAll(keepingCapacity: false)
            fragmentedStarted = false
            flushIfMarked(packet)
        }
    }

    private func makeSampleBuffer(_ buffer: inout Data, timestamp: UInt32) -> CMSampleBuffer? {
        guard formatDescription != nil else {
            return nil
        }
        let presentationTimeStamp: CMTime = self.timestamp.convert(timestamp)
        let units = nalUnitReader.read(&buffer, type: H264NALUnit.self)
        var blockBuffer: CMBlockBuffer?
        // Build the AVCC (length-prefixed) buffer FORWARD from the parsed units.
        // The previous in-place ISOTypeBufferUtil.toNALFileFormat conversion is
        // unsafe here: a written 4-byte length of 256–511 is 00 00 01 xx, which
        // its continuing reverse scan re-matches as a start code and "converts"
        // again — corrupting the access unit (VT kVTVideoDecoderBadDataErr -12909
        // on every frame). NALUnitReader.read returns units last-first, so append
        // them reversed to preserve decode order.
        var avcc = Data(capacity: buffer.count)
        for unit in units.reversed() {
            let unitData = unit.data
            var length = UInt32(unitData.count).bigEndian
            withUnsafeBytes(of: &length) { avcc.append(contentsOf: $0) }
            avcc.append(unitData)
        }
        buffer = avcc
        blockBuffer = buffer.makeBlockBuffer()
        var sampleSizes: [Int] = []
        var sampleBuffer: CMSampleBuffer?
        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: presentationTimeStamp,
            decodeTimeStamp: .invalid
        )
        sampleSizes.append(buffer.count)
        guard let blockBuffer, CMSampleBufferCreate(
                allocator: kCFAllocatorDefault,
                dataBuffer: blockBuffer,
                dataReady: true,
                makeDataReadyCallback: nil,
                refcon: nil,
                formatDescription: formatDescription,
                sampleCount: sampleSizes.count,
                sampleTimingEntryCount: 1,
                sampleTimingArray: &timing,
                sampleSizeEntryCount: sampleSizes.count,
                sampleSizeArray: &sampleSizes,
                sampleBufferOut: &sampleBuffer) == noErr else {
            return nil
        }
        sampleBuffer?.isNotSync = !units.contains { $0.type == .idr }
        return sampleBuffer
    }

    private func makeFormatDescription() -> CMFormatDescription? {
        guard let pictureParameterSets, let sequenceParameterSets else {
            return nil
        }
        let pictureParameterSetArray = [pictureParameterSets.bytes]
        let sequenceParameterSetArray = [sequenceParameterSets.bytes]
        return pictureParameterSetArray[0].withUnsafeBytes { (ppsBuffer: UnsafeRawBufferPointer) -> CMFormatDescription? in
            guard let ppsBaseAddress = ppsBuffer.baseAddress else {
                return nil
            }
            return sequenceParameterSetArray[0].withUnsafeBytes { (spsBuffer: UnsafeRawBufferPointer) -> CMFormatDescription? in
                guard let spsBaseAddress = spsBuffer.baseAddress else {
                    return nil
                }
                let pointers: [UnsafePointer<UInt8>] = [
                    spsBaseAddress.assumingMemoryBound(to: UInt8.self),
                    ppsBaseAddress.assumingMemoryBound(to: UInt8.self)
                ]
                let sizes: [Int] = [spsBuffer.count, ppsBuffer.count]
                let nalUnitHeaderLength: Int32 = 4
                var formatDescriptionOut: CMFormatDescription?
                CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault,
                    parameterSetCount: pointers.count,
                    parameterSetPointers: pointers,
                    parameterSetSizes: sizes,
                    nalUnitHeaderLength: nalUnitHeaderLength,
                    formatDescriptionOut: &formatDescriptionOut
                )
                return formatDescriptionOut
            }
        }
    }
}

extension RTPH264Packetizer: RTPJitterBufferDelegate {
    // MARK: RTPJitterBufferDelegate
    func jitterBuffer(_ buffer: RTPJitterBuffer<RTPH264Packetizer>, sequenced: RTPPacket) {
        decode(sequenced)
    }
}
