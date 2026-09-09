// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CardKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "CardKit", targets: ["CardKit"])
    ],
    targets: [
        .target(name: "CardKit"),
        .testTarget(name: "CardKitTests", dependencies: ["CardKit"])
    ]
)
