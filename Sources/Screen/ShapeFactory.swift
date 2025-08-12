import Accelerate
import CoreMedia
import Foundation

protocol Shape {
    func makeCGImage() -> CGImage?
}

final class ShapeFactory {
    private var imageBuffers: [String: vImage_Buffer] = [:]
    private var roundedSquareShape = RoundedSquareShape()

    func cornerRadius(_ size: CGSize, cornerRadius: CGFloat) -> vImage_Buffer? {
        let key = "\(size.width):\(size.height):\(cornerRadius)"
        if let buffer = imageBuffers[key] {
            return buffer
        }
        roundedSquareShape.rect = .init(origin: .zero, size: size)
        roundedSquareShape.cornerRadius = cornerRadius
        guard
            let image = roundedSquareShape.makeCGImage() else {
            return nil
        }
        imageBuffers[key] = try? vImage_Buffer(cgImage: image)
        return imageBuffers[key]
    }

    func removeAll() {
        for buffer in imageBuffers.values {
            buffer.free()
        }
        imageBuffers.removeAll()
    }
}
