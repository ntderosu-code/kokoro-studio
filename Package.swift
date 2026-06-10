// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KokoroStudio",
    platforms: [.macOS(.v14)],
    targets: [
        .systemLibrary(name: "CSherpaOnnx", path: "Sources/CSherpaOnnx"),
        .executableTarget(
            name: "KokoroStudio",
            dependencies: ["CSherpaOnnx"],
            exclude: ["CLAUDE.md", "Views/CLAUDE.md"],
            linkerSettings: [
                .unsafeFlags([
                    "-Lvendor/sherpa-onnx/lib",
                    "-lsherpa-onnx-c-api",
                    "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
                    "-Xlinker", "-rpath", "-Xlinker", "vendor/sherpa-onnx/lib",
                ])
            ]
        ),
        .testTarget(name: "KokoroStudioTests", dependencies: ["KokoroStudio"]),
    ]
)
