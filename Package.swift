// swift-tools-version: 6.0
import Foundation
import PackageDescription

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let privacyPlist = root.appendingPathComponent("Sources/PrinterBench/Info.plist").path

let package = Package(
    name: "PlatenKit",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "PlatenKit", targets: ["PlatenKit"]),
        .executable(name: "printer-bench", targets: ["PrinterBench"])
    ],
    targets: [
        .target(name: "PlatenKit", resources: [.copy("Resources/Karla-Variable.ttf"), .copy("Resources/OFL.txt")]),
        .executableTarget(
            name: "PrinterBench", dependencies: ["PlatenKit"], exclude: ["Info.plist"],
            linkerSettings: [.unsafeFlags([
                "-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", privacyPlist
            ], .when(platforms: [.macOS]))]
        ),
        .testTarget(
            name: "PlatenKitTests", dependencies: ["PlatenKit"],
            resources: [.copy("Fixtures/moon-gray-284.png")]
        )
    ]
)
