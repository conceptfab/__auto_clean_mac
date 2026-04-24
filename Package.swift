// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AutoCleanMac",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "AutoCleanMacCore",
            path: "Sources/AutoCleanMacCore"
        ),
        .executableTarget(
            name: "AutoCleanMac",
            dependencies: ["AutoCleanMacCore"],
            path: "Sources/AutoCleanMac"
        ),
        .testTarget(
            name: "AutoCleanMacCoreTests",
            dependencies: ["AutoCleanMacCore"],
            path: "Tests/AutoCleanMacCoreTests"
        ),
        .testTarget(
            name: "AutoCleanMacTests",
            dependencies: ["AutoCleanMac"],
            path: "Tests/AutoCleanMacTests"
        ),
    ]
)
