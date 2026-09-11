// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "XIXData",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "XIXData", targets: ["XIXData"])],
    dependencies: [
        .package(path: "../XIXScoring"),
        .package(path: "../XIXModels"),
        .package(url: "https://github.com/supabase/supabase-swift.git", from: "2.55.0"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.11.0"),
    ],
    targets: [
        .target(
            name: "XIXData",
            dependencies: [
                "XIXScoring", "XIXModels",
                .product(name: "Supabase", package: "supabase-swift"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ]),
        .testTarget(name: "XIXDataTests", dependencies: ["XIXData"]),
    ]
)
