// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacPaper",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MacPaper", targets: ["MacPaper"])
    ],
    targets: [
        .executableTarget(
            name: "MacPaper",
            path: "Sources/MacPaper",
            exclude: ["Resources"],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("AVKit"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("IOKit")
            ]
        )
    ]
)
