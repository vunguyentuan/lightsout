// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "LightsOut",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "LightsOut",
            path: "Sources/LightsOut",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("IOKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
    ]
)
