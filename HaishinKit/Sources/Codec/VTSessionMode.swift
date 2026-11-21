import Foundation
import VideoToolbox

enum VTSessionMode {
    case compression
    case decompression

    func makeSession(_ videoCodec: VideoCodec) throws -> any VTSessionConvertible {
        switch self {
        case .compression:
            var session: VTCompressionSession?
            var status = VTCompressionSessionCreate(
                allocator: kCFAllocatorDefault,
                width: Int32(videoCodec.settings.videoSize.width),
                height: Int32(videoCodec.settings.videoSize.height),
                codecType: videoCodec.settings.format.codecType,
                encoderSpecification: videoCodec.settings.makeEncoderSpecification(),
                imageBufferAttributes: videoCodec.makeImageBufferAttributes(.compression) as CFDictionary?,
                compressedDataAllocator: nil,
                outputCallback: nil,
                refcon: nil,
                compressionSessionOut: &session
            )
            guard status == noErr, let session else {
                throw VTSessionError.failedToCreate(status: status)
            }
            status = session.setOptions(videoCodec.settings.makeOptions())
            guard status == noErr else {
                throw VTSessionError.failedToPrepare(status: status)
            }
            status = session.prepareToEncodeFrames()
            guard status == noErr else {
                throw VTSessionError.failedToPrepare(status: status)
            }
            if let expectedFrameRate = videoCodec.settings.expectedFrameRate {
                status = session.setOption(.init(key: .expectedFrameRate, value: expectedFrameRate as CFNumber))
            }
            videoCodec.frameInterval = videoCodec.settings.frameInterval
            return session
        case .decompression:
            guard let formatDescription = videoCodec.inputFormat else {
                throw VTSessionError.failedToCreate(status: kVTParameterErr)
            }
            var session: VTDecompressionSession?
            let status = VTDecompressionSessionCreate(
                allocator: kCFAllocatorDefault,
                formatDescription: formatDescription,
                decoderSpecification: nil,
                imageBufferAttributes: videoCodec.makeImageBufferAttributes(.decompression) as CFDictionary?,
                outputCallback: nil,
                decompressionSessionOut: &session
            )
            guard let session, status == noErr else {
                throw VTSessionError.failedToCreate(status: status)
            }
            return session
        }
    }
}
