// swift-tools-version: 6.0
import PackageDescription

// TskCore is the platform-agnostic heart of the app: all business logic
// lives here. It depends on nothing but the standard library + Foundation,
// so its behavior is unit-tested with `swift test` on any platform — no
// Xcode or simulator required. The iOS app target in App/ is a thin UI
// layer on top.
let package = Package(
    name: "TskCore",
    platforms: [.iOS(.v13), .macOS(.v10_15)],
    products: [
        .library(name: "TskCore", targets: ["TskCore"]),
    ],
    targets: [
        .target(name: "TskCore"),
        .testTarget(
            name: "TskCoreTests",
            dependencies: ["TskCore"]
        ),
    ]
)
