import AVFoundation
import CoreImage
import HaishinKit

final class MonochromeEffect: VideoEffect {
    let filter: CIFilter? = CIFilter(name: "CIColorMonochrome")

    func execute(_ image: CIImage) -> CIImage {
        guard let filter else {
            return image
        }
        filter.setValue(image, forKey: "inputImage")
        filter.setValue(CIColor(red: 0.75, green: 0.75, blue: 0.75), forKey: "inputColor")
        filter.setValue(1.0, forKey: "inputIntensity")
        return filter.outputImage ?? image
    }
}

final class VividEffect: VideoEffect {
    let filter: CIFilter? = CIFilter(name: "CIColorControls")

    func execute(_ image: CIImage) -> CIImage {
        guard let filter else {
            return image
        }
        filter.setValue(image, forKey: "inputImage")
        filter.setValue(1.5, forKey: "inputSaturation")
        filter.setValue(1.15, forKey: "inputContrast")
        return filter.outputImage ?? image
    }
}

final class WarmEffect: VideoEffect {
    let filter: CIFilter? = CIFilter(name: "CITemperatureAndTint")
    let controls: CIFilter? = CIFilter(name: "CIColorControls")

    func execute(_ image: CIImage) -> CIImage {
        guard let filter, let controls else {
            return image
        }
        filter.setValue(image, forKey: "inputImage")
        filter.setValue(CIVector(x: 6500, y: 0), forKey: "inputNeutral")
        filter.setValue(CIVector(x: 4000, y: 0), forKey: "inputTargetNeutral")
        guard let warmed = filter.outputImage else { return image }

        controls.setValue(warmed, forKey: "inputImage")
        controls.setValue(1.1, forKey: "inputSaturation")
        controls.setValue(1.05, forKey: "inputContrast")
        return controls.outputImage ?? image
    }
}
