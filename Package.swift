// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "FocusWallpaper",
    platforms: [.macOS(.v12)],
    products: [.executable(name: "FocusWallpaper", targets: ["FocusWallpaper"])],
    targets: [
        .target(name: "FocusWallpaperCore"),
        .executableTarget(name: "FocusWallpaper", dependencies: ["FocusWallpaperCore"],
            linkerSettings: [.linkedFramework("AppKit")]),
        .testTarget(name: "FocusWallpaperCoreTests", dependencies: ["FocusWallpaperCore"])
    ]
)
