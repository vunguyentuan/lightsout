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
            dependencies: ["LidAwakeShared", .product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/LightsOut",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("IOKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
        .executableTarget(
            name: "LightsOutHelper",
            dependencies: ["LidAwakeShared"],
            path: "Sources/LightsOutHelper",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .target(
            name: "LidAwakeShared",
            path: "Sources/LidAwakeShared",
            linkerSettings: [.linkedFramework("Security")]
        ),
        .testTarget(
            name: "LightsOutTests",
            dependencies: ["LightsOut", "LidAwakeShared"],
            path: "Tests/LightsOutTests"
        ),
    ]
)
