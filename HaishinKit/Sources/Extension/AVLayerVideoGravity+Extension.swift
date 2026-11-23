import AVFoundation
import Foundation

extension AVLayerVideoGravity {
    var snapshotValue: String {
        switch self {
        case .resize: return "resize"
        case .resizeAspect: return "resizeAspect"
        case .resizeAspectFill: return "resizeAspectFill"
        default: return rawValue
        }
    }

    init(snapshotValue: String) {
        switch snapshotValue {
        case "resize": self = .resize
        case "resizeAspect": self = .resizeAspect
        case "resizeAspectFill": self = .resizeAspectFill
        default: self.init(rawValue: snapshotValue)
        }
    }

    func scale(_ display: CGSize, image: CGSize) -> CGAffineTransform {
        switch self {
        case .resize:
            return .init(scaleX: display.width / image.width, y: display.height / image.height)
        case .resizeAspect:
            let scale = min(display.width / image.width, display.height / image.height)
            return .init(scaleX: scale, y: scale)
        case .resizeAspectFill:
            let scale = max(display.width / image.width, display.height / image.height)
            return .init(scaleX: scale, y: scale)
        default:
            return .init(scaleX: 1.0, y: 1.0)
        }
    }

    func region(_ display: CGRect, image: CGRect) -> CGRect {
        switch self {
        case .resize:
            return image
        case .resizeAspect:
            return image
        case .resizeAspectFill:
            let x = abs(display.width - image.width) / 2
            let y = abs(display.height - image.height) / 2
            return .init(origin: .init(x: x, y: y), size: display.size)
        default:
            return image
        }
    }
}
