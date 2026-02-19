// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Poof",
    platforms: [
        .macOS(.v14),
    ],
    dependencies: [
        .package(url: "https://github.com/LebJe/TOMLKit", from: "0.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "Poof",
            dependencies: [
                "TOMLKit",
            ],
            exclude: [
                "Info.plist",
                "Poof.icon",
            ],
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "PoofTests",
            dependencies: [
                "Poof",
            ]
        ),
    ]
)
