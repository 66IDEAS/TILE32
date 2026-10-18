// swift-tools-version: 6.0
import PackageDescription

// Module layout and dependency rules: specs/architecture.md, section 1 and TA-2.
// TileCore stays pure (Foundation and CoreGraphics value types only).
let package = Package(
    name: "TileKit",
    platforms: [.macOS("27.0")],
    products: [
        .executable(name: "TILE32", targets: ["TILE32"]),
        .executable(name: "FakeWindows", targets: ["FakeWindows"]),
    ],
    targets: [
        .target(name: "TileCore"),
        .target(name: "TileLog"),
        .target(name: "TileGeometry", dependencies: ["TileCore", "TileLog"]),
        .target(name: "TileSpaces", dependencies: ["TileGeometry", "TileLog"]),
        .target(name: "TileAX", dependencies: ["TileCore", "TileGeometry", "TileLog"]),
        .target(name: "TileEngine", dependencies: ["TileCore", "TileGeometry", "TileSpaces", "TileAX", "TileLog"]),
        .target(name: "TileInput", dependencies: ["TileCore", "TileGeometry", "TileSpaces", "TileEngine", "TileLog"]),
        .target(name: "TileUI", dependencies: ["TileCore", "TileEngine", "TileLog"]),
        .executableTarget(
            name: "TILE32",
            dependencies: ["TileCore", "TileLog", "TileGeometry", "TileSpaces", "TileAX", "TileEngine", "TileInput", "TileUI"]
        ),
        .executableTarget(name: "FakeWindows"),
        .testTarget(name: "TileCoreTests", dependencies: ["TileCore"]),
        .testTarget(name: "TileGeometryTests", dependencies: ["TileGeometry"]),
        .testTarget(name: "TileSpacesTests", dependencies: ["TileSpaces"]),
        .testTarget(name: "TileInputTests", dependencies: ["TileInput"]),
        .testTarget(name: "TileEngineTests", dependencies: ["TileEngine", "TileCore", "TileAX", "TileGeometry", "TileSpaces"]),
    ]
)
