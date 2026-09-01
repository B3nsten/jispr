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
        // Pure logic, no AppKit. Unit tested.
        .target(
            name: "JisprCore",
            path: "Sources/JisprCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Jispr",
            dependencies: [
                "JisprCore",
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            path: "Sources/Jispr",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Plain check program (`make check`). Command Line Tools ship no XCTest / Swift Testing.
        .executableTarget(
            name: "JisprCoreChecks",
            dependencies: ["JisprCore"],
            path: "Sources/JisprCoreChecks",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
