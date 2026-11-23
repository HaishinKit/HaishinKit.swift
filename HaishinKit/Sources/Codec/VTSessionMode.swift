import Foundation
import VideoToolbox

enum VTSessionMode {
    case compression
    case decompression

    func makeSession(_ videoCodec: VideoCodec) throws -> any VTSessionConvertible {
        switch self {
        case .compression:
            var session: VTCompressionSession?
            var status = createCompressionSession(videoCodec, encoderSpecification: videoCodec.settings.makeEncoderSpecification(), session: &session)
            if status == kVTCouldNotFindVideoEncoderErr && videoCodec.settings.isLowLatencyRateControlEnabled {
                // There is no low-latency encoder, on the iOS Simulator for example. Without this retry, VideoCodec
                // asks for one again on every frame and encodes no video.
                logger.warn("No low-latency encoder is available, so the default rate control is used.")
                status = createCompressionSession(videoCodec, encoderSpecification: nil, session: &session)
            }
            guard status == noErr, let session else {
                throw VTSessionError.failedToCreate(status: status)
            }
            status = session.setOptions(videoCodec.makeCompressionOptions())
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

    private func createCompressionSession(_ videoCodec: VideoCodec, encoderSpecification: CFDictionary?, session: inout VTCompressionSession?) -> OSStatus {
        return VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(videoCodec.settings.videoSize.width),
            height: Int32(videoCodec.settings.videoSize.height),
            codecType: videoCodec.settings.format.codecType,
            encoderSpecification: encoderSpecification,
            imageBufferAttributes: videoCodec.makeImageBufferAttributes(.compression) as CFDictionary?,
            compressedDataAllocator: nil,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &session
        )
    }
}
