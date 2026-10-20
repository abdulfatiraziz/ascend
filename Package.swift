// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Ascend",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Ascend", targets: ["Ascend"]), .executable(name: "AscendChecks", targets: ["AscendChecks"])],
    targets: [
        .target(name: "AscendCore"),
        .executableTarget(name: "Ascend", dependencies: ["AscendCore"], exclude: ["Resources/Avatar"],
            resources: [.copy("Resources/Portraits")]),
        .executableTarget(name: "AscendChecks", dependencies: ["AscendCore"], path: "Tests/AscendCoreTests")
    ],
    swiftLanguageModes: [.v5]
)
