// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SuprSendSwift",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "SuprSendSwift",
            targets: ["SuprSendSwift"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/ashleymills/Reachability.swift",
            branch: "master"
        )
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "SuprSendSwift",
            dependencies: [
                .product(name: "Reachability", package: "reachability.swift"),
            ],
            exclude: ["Example", "Docs"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "SuprSendSwiftTests",
            dependencies: ["SuprSendSwift"],
            exclude: ["Example", "Docs"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
