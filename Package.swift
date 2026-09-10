// swift-tools-version: 5.6

import PackageDescription

let package = Package(
    name: "SuprSend",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "SuprSend",
            targets: ["SuprSend"]
        )
    ],
    targets: [
        .target(
            name: "SuprSend"
        ),
        .testTarget(
            name: "SuprSendTests",
            dependencies: ["SuprSend"]
        ),
    ]
)
