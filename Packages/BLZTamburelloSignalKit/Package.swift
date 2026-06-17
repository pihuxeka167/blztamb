// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "BLZTamburelloSignalKit",
    platforms: [
        .iOS(.v16),
        .macOS(.v10_15)
    ],
    products: [
        .library(
            name: "BLZTamburelloSignalKit",
            targets: ["BLZTamburelloSignalKit"]
        )
    ],
    targets: [
        .target(
            name: "BLZTamburelloSignalKit",
            path: "Sources/BLZTamburelloSignalKit"
        )
    ]
)
