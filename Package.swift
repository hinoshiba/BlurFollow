// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "BlurFollow",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "BlurFollow", targets: ["BlurFollow"])
    ],
    targets: [
        .executableTarget(
            name: "BlurFollow",
            path: "BlurFollow",
            exclude: ["Resources"]
        ),
        .testTarget(
            name: "BlurFollowTests",
            dependencies: ["BlurFollow"],
            path: "BlurFollowTests"
        )
    ]
)
