// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Cyberpad",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Cyberpad",
            path: "Sources/Cyberpad",
            linkerSettings: [
                .linkedFramework("CoreAudio"),
                .linkedFramework("IOKit"),
                .linkedFramework("Network"),
                .linkedFramework("Security"),
            ]
        )
    ]
)
