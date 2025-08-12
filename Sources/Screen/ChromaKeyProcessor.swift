import Accelerate
import Foundation
import simd

/// A marker type with a chroma key processable screen object.
public protocol ChromaKeyProcessable {
    /// Specifies the chroma key color.
    var chromaKeyColor: CGColor? { get set }
}

final class ChromaKeyProcessor {
    static let noFlags = vImage_Flags(kvImageNoFlags)
    static let labColorSpace = CGColorSpace(name: CGColorSpace.genericLab)!

    enum Error: Swift.Error {
        case invalidState
    }

    private let entriesPerChannel = 32
    private let sourceChannelCount = 3
    private let destinationChannelCount = 1

    private let srcFormat = vImage_CGImageFormat(
        bitsPerComponent: 32,
        bitsPerPixel: 32 * 3,
        colorSpace: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: kCGBitmapByteOrder32Host.rawValue | CGBitmapInfo.floatComponents.rawValue | CGImageAlphaInfo.none.rawValue))

    private let destFormat = vImage_CGImageFormat(
        bitsPerComponent: 32,
        bitsPerPixel: 32 * 3,
        colorSpace: labColorSpace,
        bitmapInfo: CGBitmapInfo(rawValue: kCGBitmapByteOrder32Host.rawValue | CGBitmapInfo.floatComponents.rawValue | CGImageAlphaInfo.none.rawValue))

    private var tables: [CGColor: vImage_MultidimensionalTable] = [:]
    private var outputF: [String: vImage_Buffer] = [:]
    private var output8: [String: vImage_Buffer] = [:]
    private var buffers: [String: [vImage_Buffer]] = [:]
    private let converter: vImageConverter
    private var maxFloats: [Float] = [1.0, 1.0, 1.0, 1.0]
    private var minFloats: [Float] = [0.0, 0.0, 0.0, 0.0]

    init() throws {
        guard let srcFormat, let destFormat else {
            throw Error.invalidState
        }
        converter = try vImageConverter.make(sourceFormat: srcFormat, destinationFormat: destFormat)
    }

    deinit {
        tables.forEach { vImageMultidimensionalTable_Release($0.value) }
        output8.forEach { $0.value.free() }
        outputF.forEach { $0.value.free() }
        buffers.forEach { $0.value.forEach { $0.free() } }
    }

    func makeMask(_ source: inout vImage_Buffer, chromeKeyColor: CGColor) throws -> vImage_Buffer {
        let key = "\(source.width):\(source.height)"
        if tables[chromeKeyColor] == nil {
            tables[chromeKeyColor] = try makeLookUpTable(chromeKeyColor, tolerance: 60)
        }
        if outputF[key] == nil {
            outputF[key] = try vImage_Buffer(width: Int(source.width), height: Int(source.height), bitsPerPixel: 32)
        }
        if output8[key] == nil {
            output8[key] = try vImage_Buffer(width: Int(source.width), height: Int(source.height), bitsPerPixel: 8)
        }
        guard
            let table = tables[chromeKeyColor],
            let dest = outputF[key] else {
            throw Error.invalidState
        }
        var dests: [vImage_Buffer] = [dest]
        let srcs = try makePlanarFBuffers(&source)
        vImageMultiDimensionalInterpolatedLookupTable_PlanarF(
            srcs,
            &dests,
            nil,
            table,
            kvImageFullInterpolation,
            vImage_Flags(kvImageNoFlags)
        )
        guard var result = output8[key] else {
            throw Error.invalidState
        }
        vImageConvert_PlanarFtoPlanar8(&dests[0], &result, 1.0, 0.0, Self.noFlags)
        return result
    }

    private func makePlanarFBuffers(_ source: inout vImage_Buffer) throws -> [vImage_Buffer] {
        let key = "\(source.width):\(source.height)"
        if buffers[key] == nil {
            buffers[key] = [
                try vImage_Buffer(width: Int(source.width), height: Int(source.height), bitsPerPixel: 32),
                try vImage_Buffer(width: Int(source.width), height: Int(source.height), bitsPerPixel: 32),
                try vImage_Buffer(width: Int(source.width), height: Int(source.height), bitsPerPixel: 32),
                try vImage_Buffer(width: Int(source.width), height: Int(source.height), bitsPerPixel: 32)
            ]
        }
        guard var buffers = buffers[key] else {
            throw Error.invalidState
        }
        vImageConvert_ARGB8888toPlanarF(
            &source,
            &buffers[0],
            &buffers[1],
            &buffers[2],
            &buffers[3],
            &maxFloats,
            &minFloats,
            Self.noFlags)
        return [
            buffers[1],
            buffers[2],
            buffers[3]
        ]
    }

    private func makeLookUpTable(_ chromaKeyColor: CGColor, tolerance: Float) throws -> vImage_MultidimensionalTable? {
        let ramp = vDSP.ramp(in: 0 ... 1.0, count: Int(entriesPerChannel))
        let lookupTableElementCount = Int(pow(Float(entriesPerChannel), Float(sourceChannelCount))) * Int(destinationChannelCount)
        var lookupTableData = [UInt16].init(repeating: 0, count: lookupTableElementCount)
        let chromaKeyRGB = chromaKeyColor.components ?? [0, 0, 0]
        let chromaKeyLab = try rgbToLab(
            r: chromaKeyRGB[0],
            g: chromaKeyRGB.count > 1 ? chromaKeyRGB[1] : chromaKeyRGB[0],
            b: chromaKeyRGB.count > 2 ? chromaKeyRGB[2] : chromaKeyRGB[0]
        )
        var bufferIndex = 0
        for red in ramp {
            for green in ramp {
                for blue in ramp {
                    let lab = try rgbToLab(r: red, g: green, b: blue)
                    let distance = simd_distance(chromaKeyLab, lab)
                    let contrast = Float(20)
                    let offset = Float(0.25)
                    let alpha = saturate(tanh(((distance / tolerance ) - 0.5 - offset) * contrast))
                    lookupTableData[bufferIndex] = UInt16(alpha * Float(UInt16.max))
                    bufferIndex += 1
                }
            }
        }
        var entryCountPerSourceChannel = [UInt8](repeating: UInt8(entriesPerChannel), count: sourceChannelCount)
        let result = vImageMultidimensionalTable_Create(
            &lookupTableData,
            3,
            1,
            &entryCountPerSourceChannel,
            kvImageMDTableHint_Float,
            vImage_Flags(kvImageNoFlags),
            nil)
        vImageMultidimensionalTable_Retain(result)
        return result
    }

    private func rgbToLab(r: CGFloat, g: CGFloat, b: CGFloat) throws -> SIMD3<Float> {
        var data: [Float] = [Float(r), Float(g), Float(b)]
        var srcPixelBuffer = data.withUnsafeMutableBufferPointer { pointer in
            vImage_Buffer(data: pointer.baseAddress, height: 1, width: 1, rowBytes: 4 * 3)
        }
        var destPixelBuffer = try vImage_Buffer(width: 1, height: 1, bitsPerPixel: 32 * 3)
        vImageConvert_AnyToAny(converter, &srcPixelBuffer, &destPixelBuffer, nil, vImage_Flags(kvImageNoFlags))
        defer {
            destPixelBuffer.free()
        }
        let result = destPixelBuffer.data.assumingMemoryBound(to: Float.self)
        return .init(
            result[0],
            result[1],
            result[2]
        )
    }

    private func saturate<T: FloatingPoint>(_ x: T) -> T {
        return min(max(0, x), 1)
    }
}
