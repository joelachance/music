// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MiniSpotify",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MiniSpotify", targets: ["MiniSpotify"]),
        .library(name: "MiniSpotifyCore", targets: ["MiniSpotifyCore"])
    ],
    targets: [
        .target(name: "MiniSpotifyCore"),
        .executableTarget(
            name: "MiniSpotify",
            dependencies: ["MiniSpotifyCore"]
        ),
        .executableTarget(
            name: "MiniSpotifyChecks",
            dependencies: ["MiniSpotifyCore"],
            path: "Tests/MiniSpotifyChecks"
        )
    ]
)
