import CoreMedia
import CoreVideo
import Foundation
import AOMHaishinKit

func reference() throws -> CMSampleBuffer {
    var image: CVPixelBuffer?
    guard CVPixelBufferCreate(nil, 64, 48, kCVPixelFormatType_420YpCbCr8Planar,
        [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &image) == kCVReturnSuccess,
          let image else { throw AOMVideoCodecError.unsupportedFormat }
    CVPixelBufferLockBaseAddress(image, [])
    for plane in 0..<3 {
        memset(CVPixelBufferGetBaseAddressOfPlane(image, plane), plane == 0 ? 80 : 128,
            CVPixelBufferGetBytesPerRowOfPlane(image, plane) * CVPixelBufferGetHeightOfPlane(image, plane))
    }
    CVPixelBufferUnlockBaseAddress(image, [])
    var description: CMFormatDescription?
    var sample: CMSampleBuffer?
    guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: image, formatDescriptionOut: &description) == noErr,
          let description else { throw AOMVideoCodecError.unsupportedFormat }
    var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30), presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
    guard CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: image, formatDescription: description,
        sampleTiming: &timing, sampleBufferOut: &sample) == noErr, let sample else { throw AOMVideoCodecError.unsupportedFormat }
    return sample
}

do {
    let encoder = try AOMVideoEncoder(settings: .init(videoSize: CGSize(width: 64, height: 48)))
    let decoder = try AOMVideoDecoder()
    let packets = try encoder.encode(reference()) + encoder.finish()
    let decoded = try packets.flatMap { try decoder.decode($0) }
    guard decoded.count == 1, decoded[0].presentationTimeStamp == .zero, let image = decoded[0].imageBuffer,
          CVPixelBufferGetWidth(image) == 64, CVPixelBufferGetHeight(image) == 48 else {
        throw AOMVideoCodecError.unsupportedFormat
    }
    print("Standalone AV1: encoded and decoded one frame")
}
