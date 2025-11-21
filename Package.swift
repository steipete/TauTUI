// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// Current package version
private let packageVersion = "0.1.1"

let package = Package(
    name: "TauTUI",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "TauTUI",
            targets: ["TauTUI"]),
        .executable(
            name: "ChatDemo",
            targets: ["ChatDemo"]),
        .executable(
            name: "KeyTester",
            targets: ["KeyTester"]),
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
            ],
            swiftSettings: [
                .unsafeFlags(["-strict-concurrency=complete"], .when(platforms: [.macOS, .linux])),
            ]),
        .target(
            name: "TauTUIInternal",
            dependencies: ["TauTUI"],
            path: "Sources/TauTUIInternal",
            swiftSettings: [
                .unsafeFlags(["-strict-concurrency=complete"], .when(platforms: [.macOS, .linux])),
            ]),
        .executableTarget(
            name: "ChatDemo",
            dependencies: ["TauTUI"],
            path: "Examples/ChatDemo"),
        .executableTarget(
            name: "KeyTester",
            dependencies: ["TauTUI"],
            path: "Examples/KeyTester"),
        .executableTarget(
            name: "TTYSampler",
            dependencies: ["TauTUI"],
            path: "Examples/TTYSampler",
            resources: [
                .copy("sample.json"),
                .copy("select.json"),
            ]),
        .testTarget(
            name: "TauTUITests",
            dependencies: ["TauTUI", "TauTUIInternal"],
            path: "Tests/TauTUITests"),
    ])
