import Foundation
import VideoToolbox

enum VTSessionMode {
    case compression
    case decompression

    func makeSession(settings: VideoCodecSettings, inputFormat: CMFormatDescription) throws -> any VTSessionConvertible {
        switch self {
        case .compression:
            var session: VTCompressionSession?
            var status = VTCompressionSessionCreate(
                allocator: kCFAllocatorDefault,
                width: Int32(settings.videoSize.width),
                height: Int32(settings.videoSize.height),
                codecType: settings.format.codecType,
                encoderSpecification: settings.makeEncoderSpecification(),
                imageBufferAttributes: [kCVPixelBufferPixelFormatTypeKey: CMFormatDescriptionGetMediaSubType(inputFormat)] as CFDictionary,
                compressedDataAllocator: nil,
                outputCallback: nil,
                refcon: nil,
                compressionSessionOut: &session
            )
            guard status == noErr, let session else {
                throw VTSessionError.failedToCreate(status: status)
            }
            status = session.setOptions(settings.makeOptions())
            guard status == noErr else {
                throw VTSessionError.failedToPrepare(status: status)
            }
            status = session.prepareToEncodeFrames()
            guard status == noErr else {
                throw VTSessionError.failedToPrepare(status: status)
            }
            if let expectedFrameRate = settings.expectedFrameRate {
                status = session.setOption(.init(key: .expectedFrameRate, value: expectedFrameRate as CFNumber))
                guard status == noErr else { throw VTSessionError.failedToPrepare(status: status) }
            }
            return session
        case .decompression:
            var session: VTDecompressionSession?
            let status = VTDecompressionSessionCreate(
                allocator: kCFAllocatorDefault,
                formatDescription: inputFormat,
                decoderSpecification: nil,
                imageBufferAttributes: [kCVPixelBufferIOSurfacePropertiesKey: NSDictionary(), kCVPixelBufferMetalCompatibilityKey: kCFBooleanTrue as Any] as CFDictionary,
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
