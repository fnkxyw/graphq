// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "graphq",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "graphq", targets: ["graphq"]),
        .library(name: "SketchCore", targets: ["SketchCore"]),
        .library(name: "SketchRender", targets: ["SketchRender"]),
    ],
    targets: [
        // Pure model + geometry + rough/freehand engines. No AppKit/SwiftUI.
        .target(name: "SketchCore"),
        // CoreGraphics/CoreText renderer and exporters (PNG/PDF/SVG).
        .target(
            name: "SketchRender",
            dependencies: ["SketchCore"],
            resources: [.copy("Resources/Fonts")]
        ),
        // The macOS app: SwiftUI shell + AppKit canvas.
        .executableTarget(
            name: "graphq",
            dependencies: ["SketchCore", "SketchRender"]
        ),
        .testTarget(
            name: "SketchCoreTests",
            dependencies: ["SketchCore", "SketchRender"]
        ),
    ]
)
