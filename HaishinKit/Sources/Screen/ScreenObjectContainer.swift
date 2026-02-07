import AVFoundation
import Foundation

@ScreenActor
protocol ScreenObjectContainerConvertible: AnyObject {
    func addChild(_ child: ScreenObject?) throws
    func removeChild(_ child: ScreenObject?)
    func findById(_ id: String) -> ScreenObject?
}

/// An object represents a collection of screen objects.
public class ScreenObjectContainer: ScreenObject, ScreenObjectContainerConvertible {
    /// The error domain codes.
    public enum Error: Swift.Error {
        /// An error the screen object registry throws when the app registers a screen object twice by the same instance.
        case alreadyExists
    }

    /// The total of child counts.
    public var childCounts: Int {
        children.count
    }

    internal private(set) var children: [ScreenObject] = .init()

    /// Adds the specified screen object as a child of the current screen object container.
    public func addChild(_ child: ScreenObject?) throws {
        guard let child, child != self else {
            return
        }
        if child.parent != nil {
            throw Error.alreadyExists
        }
        child.parent = self
        children.append(child)
        invalidateLayout()
    }

    /// Removes the specified screen object as a child of the current screen object container.
    public func removeChild(_ child: ScreenObject?) {
        guard let child, child.parent == self else {
            return
        }
        guard let indexOf = children.firstIndex(where: { $0 == child }) else {
            return
        }
        child.parent = nil
        children.remove(at: indexOf)
        invalidateLayout()
    }

    override public func findById(_ id: String) -> ScreenObject? {
        if self.id == id {
            return self
        }
        for child in children {
            let result = child.findById(id)
            if result != nil {
                return result
            }
        }
        return nil
    }

    override func layout(_ renderer: some ScreenRenderer) {
        bounds = makeBounds(size)
        children.forEach { child in
            if child.shouldInvalidateLayout || shouldInvalidateLayout {
                child.layout(renderer)
            }
        }
        shouldInvalidateLayout = false
    }

    override func draw(_ renderer: some ScreenRenderer) {
        guard isVisible else {
            return
        }
        children.forEach { child in
            guard child.isVisible else {
                return
            }
            child.draw(renderer)
        }
    }

    func getScreenObjects<T: ScreenObject>() -> [T] {
        var objects = children.compactMap { $0 as? T }
        children.compactMap { $0 as? ScreenObjectContainer }.forEach {
            objects += $0.getScreenObjects()
        }
        return objects
    }
}
