// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "LightsOut",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", .upToNextMinor(from: "2.9.6")),
    ],
    targets: [
        .executableTarget(
            name: "LightsOut",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/LightsOut",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("IOKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
        .testTarget(
            name: "LightsOutTests",
            dependencies: ["LightsOut"],
            path: "Tests/LightsOutTests"
        ),
    ]
)
