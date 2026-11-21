// swift-tools-version: 6.0
import PackageDescription

// A separate package proves that an application can import only the public AOM API.
let package = Package(
    name: "AOMStandaloneConsumer",
    platforms: [.macOS(.v13)],
    dependencies: [.package(name: "HaishinKit", path: "../../..")],
    targets: [.executableTarget(name: "Consumer", dependencies: [
        .product(name: "AOMHaishinKit", package: "HaishinKit")
    ])]
)
