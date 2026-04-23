// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SnapX",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(
            name: "SnapX",
            targets: ["SnapX"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "SnapX",
            path: "Sources/SnapX"
        ),
    ]
)
