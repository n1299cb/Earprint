// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "EarprintGUI",
    platforms: [
        .macOS(.v12)
    ],
    targets: [
        .executableTarget(
            name: "EarprintGUI",
            resources: [
                .copy("../../Scripts"),
                .copy("../../Resources/EmbeddedPython")
            ]
        )
    ]
)
