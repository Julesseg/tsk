// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CalendarControllerProof",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../Core"), .package(path: "../../Native")],
    targets: [.testTarget(name: "CalendarControllerProof", dependencies: [.product(name: "TskCore", package: "Core"), .product(name: "TskNative", package: "Native")], path: "Tests"),
              .testTarget(name: "TaskControlReadinessProof", path: "ReadinessTests"),
              .testTarget(name: "TaskKeyboardRegistrationProof", path: "KeyboardRegistrationTests")]
)
