// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AutoCleanMac",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "AutoCleanMacCore", targets: ["AutoCleanMacCore"]),
        .library(name: "AutoCleanMacFeature", targets: ["AutoCleanMacFeature"]),
        .executable(name: "AutoCleanMac", targets: ["AutoCleanMac"])
    ],
    targets: [
        .target(name: "AutoCleanMacCore", path: "Sources/AutoCleanMacCore"),
        .target(
            name: "AutoCleanMacFeature",
            dependencies: ["AutoCleanMacCore"],
            path: "Sources/AutoCleanMacFeature"
        ),
        .executableTarget(
            name: "AutoCleanMac",
            dependencies: ["AutoCleanMacCore", "AutoCleanMacFeature"],
            path: "Sources/AutoCleanMac"
        ),
        .testTarget(name: "AutoCleanMacCoreTests", dependencies: ["AutoCleanMacCore"], path: "Tests/AutoCleanMacCoreTests"),
        .testTarget(name: "AutoCleanMacTests", dependencies: ["AutoCleanMac"], path: "Tests/AutoCleanMacTests")
    ]
)
