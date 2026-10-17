// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TskCore",
    platforms: [.iOS(.v13), .macOS(.v10_15)],
    products: [
        .library(name: "TskCore", targets: ["TskCore"]),
    ],
    targets: [
        .target(name: "CTaskFilterRegex"),
        .target(name: "TskCore", dependencies: ["CTaskFilterRegex"]),
        .testTarget(
            name: "TskCoreTests",
            dependencies: ["TskCore"],
            resources: [.copy("Fixtures")]
        ),
    ],
    cxxLanguageStandard: .cxx17
)
