@ScreenActor
public struct ScreenObjectSnapshotFactory {
    public init() {
    }

    public func make(_ screenObject: ScreenObject) -> ScreenObjectSnapshot {
        switch screenObject {
        case let screenObjectContainer as ScreenObjectContainer:
            return ScreenObjectSnapshot(
                type: type(of: screenObject).type,
                id: screenObjectContainer.id,
                size: .init(width: Int(screenObject.size.width), height: Int(screenObject.size.height)),
                isVisible: screenObjectContainer.isVisible,
                layoutMargin: .init(
                    top: Int(screenObjectContainer.layoutMargin.top),
                    left: Int(screenObjectContainer.layoutMargin.left),
                    bottom: Int(screenObjectContainer.layoutMargin.bottom),
                    right: Int(screenObjectContainer.layoutMargin.right)
                ),
                horizontalAlignment: screenObjectContainer.horizontalAlignment.rawValue,
                verticalAlignment: screenObjectContainer.verticalAlignment.rawValue,
                elements: screenObjectContainer.elements,
                children: screenObjectContainer.children.map { make($0) }
            )
        default:
            return ScreenObjectSnapshot(
                type: type(of: screenObject).type,
                id: screenObject.id,
                size: .init(width: Int(screenObject.size.width), height: Int(screenObject.size.height)),
                isVisible: screenObject.isVisible,
                layoutMargin: .init(
                    top: Int(screenObject.layoutMargin.top),
                    left: Int(screenObject.layoutMargin.left),
                    bottom: Int(screenObject.layoutMargin.bottom),
                    right: Int(screenObject.layoutMargin.right)
                ),
                horizontalAlignment: screenObject.horizontalAlignment.rawValue,
                verticalAlignment: screenObject.verticalAlignment.rawValue,
                elements: screenObject.elements,
                children: []
            )
        }
    }

    public func make(_ screen: Screen) -> ScreenObjectSnapshot {
        return make(screen.root)
    }
}
