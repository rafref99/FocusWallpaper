// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "FocusWallpaper",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "FocusWallpaper", targets: ["FocusWallpaper"])
    ],
    targets: [
        .executableTarget(
            name: "FocusWallpaper",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Intents"),
                .linkedFramework("ServiceManagement")
            ]
        )
    ]
)
