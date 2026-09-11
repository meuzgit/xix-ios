// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "XIXScoring",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v14)],
    products: [
        .library(name: "XIXScoring", targets: ["XIXScoring"]),
    ],
    targets: [
        .target(name: "XIXScoring"),
        .testTarget(
            name: "XIXScoringTests",
            dependencies: ["XIXScoring"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
