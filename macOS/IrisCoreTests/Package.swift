// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "IrisCoreTests", platforms: [.macOS(.v15)], products: [.library(name: "IrisCore", targets: ["IrisCore"])], targets: [.target(name: "IrisCore", path: "Sources"), .testTarget(name: "IrisCoreTests", dependencies: ["IrisCore"], path: "Tests")], swiftLanguageModes: [.v5])
