// swift-tools-version: 6.0
import PackageDescription

// MyAppCore is the platform-agnostic heart of the app: all business logic
// lives here. It depends on nothing but the standard library + Foundation,
// so its behavior is unit-tested with `swift test` on any platform — no
// Xcode or simulator required. The iOS app target in App/ is a thin UI
// layer on top.
let package = Package(
    name: "MyAppCore",
    products: [
        .library(name: "MyAppCore", targets: ["MyAppCore"]),
    ],
    targets: [
        .target(name: "MyAppCore"),
        .testTarget(
            name: "MyAppCoreTests",
            dependencies: ["MyAppCore"]
        ),
    ]
)
