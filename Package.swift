// swift-tools-version: 5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SuprSend",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "SuprSend",
            targets: ["SuprSend"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/ashleymills/Reachability.swift",
            from: "5.2.4"
        )
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "SuprSend",
            dependencies: [
                .product(name: "Reachability", package: "reachability.swift"),
            ]
        ),
        .testTarget(
            name: "SuprSendTests",
            dependencies: ["SuprSend"]
        ),
    ]
)
