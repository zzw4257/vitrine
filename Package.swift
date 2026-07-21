// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Vitrine",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "Vitrine",
            path: "Sources/Vitrine",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
