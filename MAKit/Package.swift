// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MAKit",
    platforms: [.macOS(.v14)],
    products: [.library(name: "MAKit", targets: ["MAKit"])],
    targets: [
        .target(name: "MAKit"),
        .testTarget(name: "MAKitTests", dependencies: ["MAKit"], resources: [.copy("Fixtures")]),
    ]
)
