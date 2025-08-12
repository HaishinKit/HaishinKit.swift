import Accelerate
import Foundation

#if canImport(AppKit)
import AppKit
#endif

#if canImport(UIKit)
import UIKit
#endif

final class RoundedSquareShape: Shape {
    var rect: CGRect = .zero
    var cornerRadius: CGFloat = .zero

    func makeCGImage() -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: Int(rect.width),
            height: Int(rect.height),
            bitsPerComponent: 8,
            bytesPerRow: Int(rect.width),
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue).rawValue
        ) else {
            return nil
        }
        let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        #if os(macOS)
        context.setFillColor(NSColor.white.cgColor)
        #else
        context.setFillColor(UIColor.white.cgColor)
        #endif
        context.addPath(path)
        context.closePath()
        context.fillPath()
        return context.makeImage()
    }
}
