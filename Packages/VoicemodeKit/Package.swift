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
        .library(name: "VMSmart", targets: ["VMSmart"]),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", exact: "1.1.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", exact: "3.31.4"),
        .package(url: "https://github.com/huggingface/swift-transformers.git", from: "1.3.0"),
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
        // MLX needs Metal shaders that only xcodebuild compiles; build and run vm-smart with xcodebuild.
        .target(
            name: "VMSmart",
            dependencies: [
                "VMCore",
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ]
        ),
        .executableTarget(name: "vm-smart", dependencies: ["VMCore", "VMSmart"]),
        .executableTarget(name: "vm-bench", dependencies: ["VMCore", "VMAudio", "VMTranscription"]),
        .testTarget(name: "VMCoreTests", dependencies: ["VMCore"]),
        .testTarget(name: "VMTranscriptionTests", dependencies: ["VMTranscription"]),
        .testTarget(name: "VMSystemTests", dependencies: ["VMSystem"]),
    ]
)
