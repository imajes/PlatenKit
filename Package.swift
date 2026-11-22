// swift-tools-version: 6.0
import Foundation
import PackageDescription

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let privacyPlist = root.appendingPathComponent("Sources/PrinterBench/Info.plist").path

let package = Package(
    name: "WhiplashPrinting",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "WhiplashPrinting", targets: ["WhiplashPrinting"]),
        .executable(name: "printer-bench", targets: ["PrinterBench"])
    ],
    targets: [
        .target(name: "WhiplashPrinting"),
        .executableTarget(
            name: "PrinterBench", dependencies: ["WhiplashPrinting"], exclude: ["Info.plist"],
            linkerSettings: [.unsafeFlags([
                "-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", privacyPlist
            ], .when(platforms: [.macOS]))]
        ),
        .testTarget(name: "WhiplashPrintingTests", dependencies: ["WhiplashPrinting"])
    ]
)
