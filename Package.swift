// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Jispr",
    platforms: [.macOS("26.0")],
    dependencies: [
        // Runs NVIDIA Parakeet (CoreML build from Hugging Face) on-device.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.15.6"),
    ],
    targets: [
        .executableTarget(
            name: "Jispr",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            path: "Sources/Jispr",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
