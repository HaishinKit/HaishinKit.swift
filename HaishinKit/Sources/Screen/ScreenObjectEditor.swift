import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Hit testing and layout edits for direct children of a screen, performed on its rendering actor.
@ScreenActor
public final class ScreenObjectEditor {
    private let screen: Screen

    /// Creates an editor for the given screen.
    public init(screen: Screen) {
        self.screen = screen
    }

    /// Finds the frontmost visible child at a composition point, in actual drawing order.
    public func hitTest(_ point: CGPoint, where isEditable: (ScreenObject) -> Bool = { _ in true }) -> ScreenObject? {
        guard CGRect(origin: .zero, size: screen.size).contains(point), screen.root.isVisible else {
            return nil
        }
        return screen.root.children.reversed().first {
            $0 !== screen.videoTrackScreenObject && $0.isVisible && isEditable($0) && $0.bounds.contains(point)
        }
    }

    /// Positions a direct child by its top-left corner. Pass its requested size to position a new object.
    public func move(_ target: ScreenObject, to origin: CGPoint, size: CGSize? = nil) {
        guard target.parent === screen.root else { return }
        let size = size ?? target.bounds.size
        guard origin.x.isFinite, origin.y.isFinite, size.width.isFinite, size.height.isFinite,
              size.width >= 0, size.height >= 0 else {
            return
        }
        target.horizontalAlignment = .left
        target.verticalAlignment = .top
        target.layoutMargin = .init(
            top: min(max(0, origin.y), max(0, screen.size.height - size.height)),
            left: min(max(0, origin.x), max(0, screen.size.width - size.width)),
            bottom: 0,
            right: 0
        )
        target.invalidateLayout()
    }

    /// Translates the supplied bounds and scales proportionally around the anchor.
    /// Supply the returned bounds to subsequent calls within a gesture to avoid waiting for layout.
    @discardableResult
    public func transform(
        _ target: ScreenObject,
        bounds: CGRect,
        anchor: CGPoint,
        destination: CGPoint,
        scale: CGFloat = 1,
        minimumSize: CGFloat = 24
    ) -> CGRect? {
        guard target.parent === screen.root, !bounds.isEmpty,
              scale.isFinite, scale > 0, minimumSize.isFinite, minimumSize > 0,
              bounds.width.isFinite, bounds.height.isFinite, bounds.minX.isFinite, bounds.minY.isFinite,
              anchor.x.isFinite, anchor.y.isFinite, destination.x.isFinite, destination.y.isFinite else {
            return nil
        }
        let maximum = min(screen.size.width / bounds.width, screen.size.height / bounds.height)
        guard maximum.isFinite, maximum > 0 else { return nil }
        let minimum = min(maximum, max(minimumSize / bounds.width, minimumSize / bounds.height))
        let factor = scale == 1 ? 1 : min(maximum, max(minimum, scale))
        let size = CGSize(width: bounds.width * factor, height: bounds.height * factor)
        let origin = CGPoint(
            x: destination.x - (anchor.x - bounds.minX) * factor,
            y: destination.y - (anchor.y - bounds.minY) * factor
        )
        guard origin.x.isFinite, origin.y.isFinite else { return nil }
        if factor != 1 {
            if let text = target as? TextScreenObject {
                text.scaleFont(by: factor)
                text.size = CGSize(width: text.size.width * factor, height: text.size.height * factor)
                move(text, to: origin, size: size)
                let measured = text.makeBounds(text.size)
                let measuredOrigin = CGPoint(
                    x: destination.x - (anchor.x - bounds.minX) * measured.width / bounds.width,
                    y: destination.y - (anchor.y - bounds.minY) * measured.height / bounds.height
                )
                move(text, to: measuredOrigin, size: measured.size)
                return text.makeBounds(text.size)
            } else {
                target.size = size
            }
        }
        move(target, to: origin, size: size)
        return CGRect(x: target.layoutMargin.left, y: target.layoutMargin.top, width: size.width, height: size.height)
    }
}

private extension TextScreenObject {
    func scaleFont(by factor: CGFloat) {
        #if os(macOS)
        let font = attributes?[.font] as? NSFont ?? .boldSystemFont(ofSize: 32)
        var updated = attributes ?? [:]
        updated[.font] = NSFont(descriptor: font.fontDescriptor, size: font.pointSize * factor) ?? font
        #else
        let font = attributes?[.font] as? UIFont ?? .boldSystemFont(ofSize: 32)
        var updated = attributes ?? [:]
        updated[.font] = font.withSize(font.pointSize * factor)
        #endif
        attributes = updated
    }
}
