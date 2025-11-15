// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "TauTUI",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "TauTUI",
            targets: ["TauTUI"]
        ),
        .executable(
            name: "ChatDemo",
            targets: ["ChatDemo"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-markdown.git", from: "0.7.3"),
        .package(url: "https://github.com/apple/swift-system.git", from: "1.6.3"),
        .package(url: "https://github.com/ainame/swift-displaywidth.git", from: "0.0.3"),
    ],
    targets: [
        .target(
            name: "TauTUI",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "SystemPackage", package: "swift-system"),
                .product(name: "DisplayWidth", package: "swift-displaywidth"),
            ]
        ),
        .executableTarget(
            name: "ChatDemo",
            dependencies: ["TauTUI"],
            path: "Examples/ChatDemo"
        ),
        .testTarget(
            name: "TauTUITests",
            dependencies: ["TauTUI"]
        ),
    ]
)
