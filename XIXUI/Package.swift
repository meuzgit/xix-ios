// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "XIXUI",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "XIXUI", targets: ["XIXUI"])],
    dependencies: [
        .package(path: "../XIXScoring"),
        .package(path: "../XIXData"),
    ],
    targets: [
        .target(
            name: "XIXUI",
            dependencies: ["XIXScoring", "XIXData"],
            resources: [.copy("Resources/Stickers"), .copy("Resources/Audio")]),
        .testTarget(
            name: "XIXUITests",
            dependencies: ["XIXUI", "XIXScoring"],
            resources: [.copy("__Snapshots__")]),
    ]
)
