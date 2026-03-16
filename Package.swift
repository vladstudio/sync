// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Sync",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-testing.git", exact: "6.2.3")
    ],
    targets: [
        .executableTarget(
            name: "Sync",
            path: "Sources/Sync",
            resources: [.copy("Resources/RemoteIcons")]
        ),
        .testTarget(
            name: "SyncTests",
            dependencies: [
                "Sync",
                .product(name: "Testing", package: "swift-testing"),
            ]
        )
    ]
)
