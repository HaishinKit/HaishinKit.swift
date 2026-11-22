import Foundation

/// A factory responsible for creating `ScreenObject` instances
/// from a `ScreenObjectSnapshot`.
///
/// `ScreenObjectFactory` centralizes the logic for instantiating
/// concrete `ScreenObject` subclasses based on the snapshot's
/// logical type. This ensures that object creation is consistent
/// and decoupled from snapshot deserialization logic.
///
/// This factory is isolated to `ScreenActor`, making it safe to use
/// in actor-based concurrency contexts.
@ScreenActor
public struct ScreenObjectFactory {
    /// Creates a new `ScreenObjectFactory` instance.
    ///
    /// This initializer performs no configuration and exists
    /// primarily to allow explicit construction of the factory.
    public init() {
    }

    /// Creates a `ScreenObject` from the given snapshot.
    ///
    /// This method inspects the snapshot's `type` and instantiates
    /// the corresponding concrete `ScreenObject` implementation.
    /// After creation, common properties such as elements, alignment,
    /// and layout margins are applied to the resulting object.
    ///
    /// - Parameter snapshot: A snapshot describing the state and
    ///   configuration of a screen object.
    /// Unsupported types become invisible placeholders. Recapturing such a
    /// placeholder preserves its original snapshot for another platform.
    /// - Returns: A configured screen object or an invisible placeholder.
    public func make(_ snapshot: ScreenObjectSnapshot) -> ScreenObject? {
        var screenObject: ScreenObject?
        switch snapshot.type {
        case "screen", ScreenObjectContainer.type:
            let container = ScreenObjectContainer(id: snapshot.id)
            for child in snapshot.children {
                try? container.addChild(make(child))
            }
            screenObject = container
        case ImageScreenObject.type:
            screenObject = ImageScreenObject(id: snapshot.id)
        case TextScreenObject.type:
            screenObject = TextScreenObject(id: snapshot.id)
        case VideoScreenObject.type:
            screenObject = VideoScreenObject(id: snapshot.id)
        #if !os(visionOS)
        case AssetScreenObject.type:
            screenObject = AssetScreenObject(id: snapshot.id)
        #endif
        default:
            screenObject = UnsupportedScreenObject(snapshot: snapshot)
        }
        screenObject?.isVisible = screenObject is UnsupportedScreenObject ? false : snapshot.isVisible
        screenObject?.size = snapshot.size.cgSize
        screenObject?.cornerRadius = CGFloat(snapshot.cornerRadius ?? 0)
        screenObject?.elements = snapshot.elements
        screenObject?.horizontalAlignment = .init(rawValue: snapshot.horizontalAlignment) ?? .left
        screenObject?.verticalAlignment = .init(rawValue: snapshot.verticalAlignment) ?? .top
        screenObject?.layoutMargin = .init(
            top: CGFloat(snapshot.layoutMargin.top),
            left: CGFloat(snapshot.layoutMargin.left),
            bottom: CGFloat(snapshot.layoutMargin.bottom),
            right: CGFloat(snapshot.layoutMargin.right)
        )
        return screenObject
    }
}

/// Retains an unsupported platform's node without rendering or losing its serialized state.
@ScreenActor
final class UnsupportedScreenObject: ScreenObject {
    let snapshot: ScreenObjectSnapshot

    init(snapshot: ScreenObjectSnapshot) {
        self.snapshot = snapshot
        super.init(id: snapshot.id)
        isVisible = false
    }
}
