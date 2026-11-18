// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "IrisPhoneChecks", products: [.library(name: "IrisStream", targets: ["IrisStream"])], targets: [.target(name: "IrisStream", path: "Sources"), .testTarget(name: "IrisStreamTests", dependencies: ["IrisStream"], path: "Tests")])
