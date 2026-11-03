// swift-tools-version:6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.
import PackageDescription

#if swift(<6)
let swiftSettings: [SwiftSetting] = [
    .enableExperimentalFeature("ExistentialAny"),
    .enableExperimentalFeature("StrictConcurrency")
]
#else
let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny")
]
#endif

let package = Package(
    name: "HaishinKit",
    platforms: [
        .iOS(.v15),
        .tvOS(.v15),
        .macCatalyst(.v15),
        .macOS(.v12),
        .visionOS("1.3")
    ],
    products: [
        .library(name: "HaishinKit", targets: ["HaishinKit"]),
        .library(name: "VPXHaishinKit", targets: ["VPXHaishinKit"]),
        .library(name: "RTMPHaishinKit", targets: ["RTMPHaishinKit"]),
        .library(name: "SRTHaishinKit", targets: ["SRTHaishinKit"]),
        .library(name: "MoQTHaishinKit", targets: ["MoQTHaishinKit"]),
        .library(name: "RTCHaishinKit", targets: ["RTCHaishinKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/HaishinKit/libvpx-xcframework.git", from: "1.17.0"),
        .package(url: "https://github.com/HaishinKit/libdatachannel-xcframework.git", from: "0.24.6"),
        .package(url: "https://github.com/HaishinKit/libsrt-xcframework.git", from: "1.5.7"),
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.5"),
        .package(url: "https://github.com/shogo4405/Logboard.git", "2.6.0"..<"2.7.0")
    ],
    targets: [
        .target(
            name: "VPXBridge",
            dependencies: [.product(name: "libvpx", package: "libvpx-xcframework")],
            path: "VPXHaishinKit/Bridge"
        ),
        .target(
            name: "VPXHaishinKit",
            dependencies: ["HaishinKit", "VPXBridge"],
            path: "VPXHaishinKit/Sources",
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "VPXHaishinKitTests",
            dependencies: ["VPXHaishinKit", "RTMPHaishinKit", "RTCHaishinKit", "SRTHaishinKit"],
            path: "VPXHaishinKit/Tests",
            swiftSettings: swiftSettings
        ),
        .target(
            name: "HaishinKit",
            dependencies: ["Logboard"],
            path: "HaishinKit/Sources",
            swiftSettings: swiftSettings
        ),
        .target(
            name: "RTMPHaishinKit",
            dependencies: ["HaishinKit"],
            path: "RTMPHaishinKit/Sources",
            swiftSettings: swiftSettings
        ),
        .target(
            name: "SRTHaishinKit",
            dependencies: [.product(name: "libsrt", package: "libsrt-xcframework"), "HaishinKit"],
            path: "SRTHaishinKit/Sources",
            swiftSettings: swiftSettings
        ),
        .target(
            name: "MoQTHaishinKit",
            dependencies: ["HaishinKit"],
            path: "MoQTHaishinKit/Sources",
            swiftSettings: swiftSettings
        ),
        .target(
            name: "RTCHaishinKit",
            dependencies: [.product(name: "libdatachannel", package: "libdatachannel-xcframework"), "HaishinKit"],
            path: "RTCHaishinKit/Sources",
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "HaishinKitTests",
            dependencies: ["HaishinKit"],
            path: "HaishinKit/Tests",
            resources: [
                .process("Asset")
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "RTMPHaishinKitTests",
            dependencies: ["RTMPHaishinKit"],
            path: "RTMPHaishinKit/Tests",
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "SRTHaishinKitTests",
            dependencies: ["SRTHaishinKit"],
            path: "SRTHaishinKit/Tests",
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "RTCHaishinKitTests",
            dependencies: ["RTCHaishinKit"],
            path: "RTCHaishinKit/Tests",
            swiftSettings: swiftSettings
        )
    ],
    swiftLanguageModes: [.v6, .v5]
)
