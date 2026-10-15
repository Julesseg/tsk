// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TskNative",
    platforms: [.iOS(.v13), .macOS("10.15.4")],
    products: [.library(name: "TskNative", targets: ["TskNative"]), .executable(name: "tsk-native-probe", targets: ["TskNativeProbe"])],
    dependencies: [.package(path: "../Core")],
    targets: [
        .target(name: "CTaskChampion", linkerSettings: [.linkedLibrary("dl", .when(platforms: [.linux]))]),
        .target(name: "TskNative", dependencies: ["CTaskChampion", .product(name: "TskCore", package: "Core")]),
        .executableTarget(name: "TskNativeProbe", dependencies: ["TskNative"]),
        .testTarget(name: "TskNativeTests", dependencies: ["TskNative"])
    ]
)
