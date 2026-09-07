// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "tauri-plugin-cloud-storage",
    platforms: [
        .iOS(.v13),
    ],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "tauri-plugin-cloud-storage",
            type: .static,
            targets: ["tauri-plugin-cloud-storage"]),
    ],
    dependencies: [
        .package(name: "Tauri", path: "../.tauri/tauri-api")
    ],
    targets: [
        .target(
            name: "CloudStorageCore",
            path: "Sources/CloudStorageCore"
        ),
        .target(
            name: "tauri-plugin-cloud-storage",
            dependencies: [
                .byName(name: "Tauri"),
                .byName(name: "CloudStorageCore")
            ],
            path: "Sources",
            exclude: ["CloudStorageCore"]
        ),
        .testTarget(
            name: "CloudStorageCoreTests",
            dependencies: ["CloudStorageCore"],
            path: "Tests/CloudStorageCoreTests"
        )
    ]
)
