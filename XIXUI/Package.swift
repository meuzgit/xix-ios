// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "XIXUI",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "XIXUI", targets: ["XIXUI"])],
    dependencies: [
        .package(path: "../XIXScoring"),
    ],
    targets: [
        .target(
            name: "XIXUI",
            resources: [.copy("Resources/Stickers")]),
        .testTarget(
            name: "XIXUITests",
            dependencies: ["XIXUI", "XIXScoring"],
            resources: [.copy("__Snapshots__")]),
    ]
)
