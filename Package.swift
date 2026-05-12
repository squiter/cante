// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Cante",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "cante", targets: ["CanteCLI"]),
        .executable(name: "cante-overlay", targets: ["CanteOverlay"]),
        .executable(name: "cante-lyrics", targets: ["CanteLyrics"]),
        .executable(name: "cante-spotify", targets: ["CanteSpotify"])
    ],
    targets: [
        .target(
            name: "CanteCore",
            path: "Sources/CanteCore"
        ),
        .executableTarget(
            name: "CanteCLI",
            dependencies: ["CanteCore"],
            path: "Sources/CanteCLI"
        ),
        .executableTarget(
            name: "CanteOverlay",
            path: "Sources/CanteOverlay"
        ),
        .executableTarget(
            name: "CanteLyrics",
            dependencies: ["CanteCore"],
            path: "Sources/CanteLyrics"
        ),
        .executableTarget(
            name: "CanteSpotify",
            dependencies: ["CanteCore"],
            path: "Sources/CanteSpotify"
        )
    ]
)
