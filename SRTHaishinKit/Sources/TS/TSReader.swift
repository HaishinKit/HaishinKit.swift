import AVFoundation
import Foundation
import HaishinKit

/// A class represents that reads MPEG-2 transport stream data.
final class TSReader {
    /// An asynchronous sequence for reading data.
    public var output: AsyncStream<(UInt16, CMSampleBuffer)> {
        AsyncStream { continuation in
            self.continuation = continuation
        }
    }
    private var pat: TSProgramAssociation? {
        didSet {
            guard let pat else {
                return
            }
            for (channel, PID) in pat.programs {
                programs[PID] = channel
            }
            if logger.isEnabledFor(level: .trace) {
                logger.trace(programs)
            }
        }
    }
    private var pmt: [UInt16: TSProgramMap] = [:] {
        didSet {
            for pmt in pmt.values {
                for data in pmt.elementaryStreamSpecificData where esSpecData[data.elementaryPID] != data {
                    esSpecData[data.elementaryPID] = data
                }
            }
            if logger.isEnabledFor(level: .trace) {
                logger.trace(esSpecData)
            }
        }
    }
    private var programs: [UInt16: UInt16] = [:]
    private var esSpecData: [UInt16: ESSpecificData] = [:]
    private var continuation: AsyncStream<(UInt16, CMSampleBuffer)>.Continuation? {
        didSet {
            oldValue?.finish()
        }
    }
    private var nalUnitReader = NALUnitReader()
    private var formatDescriptions: [UInt16: CMFormatDescription] = [:]
    private var packetizedElementaryStreams: [UInt16: PacketizedElementaryStream] = [:]
    private var previousPresentationTimeStamps: [UInt16: CMTime] = [:]

    /// Create a  new instance.
    init() {
    }

    /// Reads transport-stream data.
    func read(_ data: Data) -> Int {
        let count = data.count / TSPacket.size
        for i in 0..<count {
            guard let packet = TSPacket(data: data.subdata(in: i * TSPacket.size..<(i + 1) * TSPacket.size)) else {
                continue
            }
            if packet.pid == 0x0000 {
                pat = TSProgramAssociation(packet.payload)
                continue
            }
            if let channel = programs[packet.pid] {
                pmt[channel] = TSProgramMap(packet.payload)
                continue
            }
            readPacketizedElementaryStream(packet)
        }
        return count * TSPacket.size
    }

    /// Clears the reader object for new transport stream.
    func clear() {
        pat = nil
        pmt.removeAll()
        programs.removeAll()
        esSpecData.removeAll()
        formatDescriptions.removeAll()
        packetizedElementaryStreams.removeAll()
        previousPresentationTimeStamps.removeAll()
        continuation = nil
    }

    private func readPacketizedElementaryStream(_ packet: TSPacket) {
        if packet.payloadUnitStartIndicator {
            if let sampleBuffer = makeSampleBuffer(packet.pid, forUpdate: true) {
                continuation?.yield((packet.pid, sampleBuffer))
            }
            packetizedElementaryStreams[packet.pid] = PacketizedElementaryStream(packet.payload)
            return
        }
        _ = packetizedElementaryStreams[packet.pid]?.append(packet.payload)
        if let sampleBuffer = makeSampleBuffer(packet.pid) {
            continuation?.yield((packet.pid, sampleBuffer))
        }
    }

    private func makeSampleBuffer(_ id: UInt16, forUpdate: Bool = false) -> CMSampleBuffer? {
        guard
            let data = esSpecData[id],
            var pes = packetizedElementaryStreams[id], pes.isEntired || forUpdate else {
            return nil
        }
        defer {
            packetizedElementaryStreams[id] = nil
        }
        let formatDescription = makeFormatDescription(data, pes: &pes)
        if let formatDescription, formatDescriptions[id] != formatDescription {
            formatDescriptions[id] = formatDescription
        }
        var isNotSync = true
        switch data.streamType {
        case .h264:
            let units = nalUnitReader.read(&pes.data, type: H264NALUnit.self)
            var annexB = Data()
            for unit in units where unit.type == .idr || unit.type == .slice {
                annexB.append(contentsOf: [0x00, 0x00, 0x00, 0x01])
                annexB.append(unit.data)
            }
            if !annexB.isEmpty {
                pes.data = annexB
            }
            isNotSync = !units.contains { $0.type == .idr }
        case .h265:
            let units = nalUnitReader.read(&pes.data, type: HEVCNALUnit.self)
            isNotSync = units.contains { $0.type == .sps }
        case .adtsAac:
            isNotSync = false
        default:
            break
        }
        let sampleBuffer = pes.makeSampleBuffer(
            data.streamType,
            previousPresentationTimeStamp: previousPresentationTimeStamps[id] ?? .invalid,
            formatDescription: formatDescriptions[id]
        )
        sampleBuffer?.isNotSync = isNotSync
        previousPresentationTimeStamps[id] = sampleBuffer?.presentationTimeStamp
        return sampleBuffer
    }

    private func makeFormatDescription(_ data: ESSpecificData, pes: inout PacketizedElementaryStream) -> CMFormatDescription? {
        switch data.streamType {
        case .adtsAac:

            return ADTSHeader(data: pes.data).makeFormatDescription()
        case .h264, .h265:
            return nalUnitReader.makeFormatDescription(&pes.data, type: data.streamType)
        default:
            return nil
        }
    }
}
