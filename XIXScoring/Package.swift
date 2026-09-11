// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "XIXScoring",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v14)],
    products: [
        .library(name: "XIXScoring", targets: ["XIXScoring"]),
        .executable(name: "xix-engine-cli", targets: ["xix-engine-cli"]),
    ],
    targets: [
        .target(name: "XIXScoring"),
        .executableTarget(name: "xix-engine-cli", dependencies: ["XIXScoring"]),
        .testTarget(
            name: "XIXScoringTests",
            dependencies: ["XIXScoring"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
