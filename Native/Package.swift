// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TskNative",
    platforms: [.iOS(.v13), .macOS(.v10_15)],
    products: [.library(name: "TskNative", targets: ["TskNative"])],
    dependencies: [.package(path: "../Core")],
    targets: [
        .target(name: "CTaskChampion", linkerSettings: [.linkedLibrary("dl", .when(platforms: [.linux]))]),
        .target(name: "TskNative", dependencies: ["CTaskChampion", .product(name: "TskCore", package: "Core")]),
        .testTarget(name: "TskNativeTests", dependencies: ["TskNative"])
    ]
)
