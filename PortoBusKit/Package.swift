// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PortoBusKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "PortoBusKit", targets: ["PortoBusKit"]),
    ],
    targets: [
        .target(
            name: "PortoBusKit",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "PortoBusKitTests",
            dependencies: ["PortoBusKit"],
            resources: [
                .copy("Fixtures"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
