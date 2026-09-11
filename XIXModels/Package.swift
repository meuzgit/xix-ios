// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "XIXModels",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v14)],
    products: [.library(name: "XIXModels", targets: ["XIXModels"])],
    dependencies: [
        .package(url: "https://github.com/supabase/supabase-swift.git", from: "2.55.0"),
    ],
    targets: [
        .target(name: "XIXModels", dependencies: [.product(name: "Supabase", package: "supabase-swift")]),
    ]
)
