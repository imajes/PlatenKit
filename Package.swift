// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WhiplashPrinting",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "WhiplashPrinting", targets: ["WhiplashPrinting"])
    ],
    targets: [
        .target(name: "WhiplashPrinting"),
        .testTarget(name: "WhiplashPrintingTests", dependencies: ["WhiplashPrinting"])
    ]
)
