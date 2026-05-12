// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Cante",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "cante-overlay", targets: ["CanteOverlay"]),
        .executable(name: "cante-lyrics", targets: ["CanteLyrics"])
    ],
    targets: [
        .executableTarget(
            name: "CanteOverlay",
            path: "Sources/CanteOverlay"
        ),
        .executableTarget(
            name: "CanteLyrics",
            path: "Sources/CanteLyrics"
        )
    ]
)
