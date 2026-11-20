// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FanControl",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "FanControl", targets: ["FanControl"]),
        .executable(name: "FanControlHelper", targets: ["FanControlHelper"]),
        .executable(name: "fanctl", targets: ["fanctl"]),
    ],
    targets: [
        .target(name: "CSMC", linkerSettings: [.linkedFramework("IOKit")]),
        .target(name: "FanKit", dependencies: ["CSMC"]),
        .executableTarget(name: "FanControl", dependencies: ["FanKit"]),
        .executableTarget(name: "FanControlHelper", dependencies: ["FanKit"]),
        .executableTarget(name: "fanctl", dependencies: ["FanKit"]),
        .testTarget(name: "FanKitTests", dependencies: ["FanKit"]),
    ],
    swiftLanguageModes: [.v5]
)
