// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "VoicemodeKit",
    defaultLocalization: "ru",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "VMCore", targets: ["VMCore"]),
        .library(name: "VMAudio", targets: ["VMAudio"]),
        .library(name: "VMTranscription", targets: ["VMTranscription"]),
        .library(name: "VMSystem", targets: ["VMSystem"]),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", exact: "1.1.0"),
    ],
    targets: [
        .target(name: "VMCore"),
        .target(name: "VMAudio", dependencies: ["VMCore"]),
        .target(
            name: "VMTranscription",
            dependencies: [
                "VMCore",
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
            ]
        ),
        .target(name: "VMSystem", dependencies: ["VMCore"]),
        .executableTarget(name: "vm-bench", dependencies: ["VMCore", "VMAudio", "VMTranscription"]),
        .testTarget(name: "VMCoreTests", dependencies: ["VMCore"]),
        .testTarget(name: "VMTranscriptionTests", dependencies: ["VMTranscription"]),
        .testTarget(name: "VMSystemTests", dependencies: ["VMSystem"]),
    ]
)
