import Accelerate
import CoreImage
import CoreVideo
import Foundation

extension CVPixelBuffer {
    enum Error: Swift.Error {
        case failedToLock(_ status: CVReturn)
        case unsupportedFormat(_ format: OSType)
    }

    static let lockFlags = CVPixelBufferLockFlags(rawValue: .zero)

    @inlinable @inline(__always)
    var size: CGSize {
        return .init(width: CVPixelBufferGetWidth(self), height: CVPixelBufferGetHeight(self))
    }

    @inlinable @inline(__always)
    var dataSize: Int {
        CVPixelBufferGetDataSize(self)
    }

    @inlinable @inline(__always)
    var pixelFormatType: OSType {
        CVPixelBufferGetPixelFormatType(self)
    }

    @inlinable @inline(__always)
    var baseAddress: UnsafeMutableRawPointer? {
        CVPixelBufferGetBaseAddress(self)
    }

    @inlinable @inline(__always)
    var planeCount: Int {
        CVPixelBufferGetPlaneCount(self)
    }

    @inlinable @inline(__always)
    var bytesPerRow: Int {
        CVPixelBufferGetBytesPerRow(self)
    }

    @inlinable @inline(__always)
    var width: Int {
        CVPixelBufferGetWidth(self)
    }

    @inlinable @inline(__always)
    var height: Int {
        CVPixelBufferGetHeight(self)
    }

    @inlinable @inline(__always)
    var formatType: OSType {
        CVPixelBufferGetPixelFormatType(self)
    }

    @inline(__always)
    func copy(_ pixelBuffer: CVPixelBuffer?) throws {
        // https://stackoverflow.com/questions/53132611/copy-a-cvpixelbuffer-on-any-ios-device
        try pixelBuffer?.mutate(.readOnly) { pixelBuffer in
            if planeCount == 0 {
                let dst = self.baseAddress
                let src = pixelBuffer.baseAddress
                let bytesPerRowSrc = pixelBuffer.bytesPerRow
                let bytesPerRowDst = bytesPerRowSrc
                if bytesPerRowSrc == bytesPerRowDst {
                    memcpy(dst, src, height * bytesPerRowSrc)
                } else {
                    var startOfRowSrc = src
                    var startOfRowDst = dst
                    for _ in 0..<height {
                        memcpy(startOfRowDst, startOfRowSrc, min(bytesPerRowSrc, bytesPerRowDst))
                        startOfRowSrc = startOfRowSrc?.advanced(by: bytesPerRowSrc)
                        startOfRowDst = startOfRowDst?.advanced(by: bytesPerRowDst)
                    }
                }
            } else {
                for plane in 0..<planeCount {
                    let dst = baseAddressOfPlane(plane)
                    let src = pixelBuffer.baseAddressOfPlane(plane)
                    let height = getHeightOfPlane(plane)
                    let bytesPerRowSrc = pixelBuffer.bytesPerRawOfPlane(plane)
                    let bytesPerRowDst = bytesPerRawOfPlane(plane)
                    if bytesPerRowSrc == bytesPerRowDst {
                        memcpy(dst, src, height * bytesPerRowSrc)
                    } else {
                        var startOfRowSrc = src
                        var startOfRowDst = dst
                        for _ in 0..<height {
                            memcpy(startOfRowDst, startOfRowSrc, min(bytesPerRowSrc, bytesPerRowDst))
                            startOfRowSrc = startOfRowSrc?.advanced(by: bytesPerRowSrc)
                            startOfRowDst = startOfRowDst?.advanced(by: bytesPerRowDst)
                        }
                    }
                }
            }
        }
    }

    @inline(__always)
    func mutate(_ lockFlags: CVPixelBufferLockFlags, lambda: (CVPixelBuffer) throws -> Void) throws {
        let status = CVPixelBufferLockBaseAddress(self, lockFlags)
        guard status == kCVReturnSuccess else {
            throw Error.failedToLock(status)
        }
        defer {
            CVPixelBufferUnlockBaseAddress(self, lockFlags)
        }
        try lambda(self)
    }

    func makeCIImage() -> CIImage {
        CIImage(cvPixelBuffer: self)
    }

    @inlinable
    @inline(__always)
    @discardableResult
    func lockBaseAddress(_ lockFlags: CVPixelBufferLockFlags = CVPixelBufferLockFlags.readOnly) -> CVReturn {
        return CVPixelBufferLockBaseAddress(self, lockFlags)
    }

    @inlinable
    @inline(__always)
    @discardableResult
    func unlockBaseAddress(_ lockFlags: CVPixelBufferLockFlags = CVPixelBufferLockFlags.readOnly) -> CVReturn {
        return CVPixelBufferUnlockBaseAddress(self, lockFlags)
    }

    @inlinable
    @inline(__always)
    func baseAddressOfPlane(_ index: Int) -> UnsafeMutableRawPointer? {
        CVPixelBufferGetBaseAddressOfPlane(self, index)
    }

    @inlinable
    @inline(__always)
    func getHeightOfPlane(_ index: Int) -> Int {
        CVPixelBufferGetHeightOfPlane(self, index)
    }

    @inlinable
    @inline(__always)
    func bytesPerRawOfPlane(_ index: Int) -> Int {
        CVPixelBufferGetBytesPerRowOfPlane(self, index)
    }
}
