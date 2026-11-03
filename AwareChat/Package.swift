// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "AwareChat",
    platforms: [
        // WiFiAware framework and NetworkListener/NetworkBrowser require iOS 26.
        .iOS(.v26),
        .macOS(.v14),
    ],
    products: [
        // An xtool project should contain exactly one library product,
        // representing the main app.
        .library(
            name: "AwareChat",
            targets: ["AwareChat"]
        ),
    ],
    targets: [
        .target(
            name: "AwareChat"
        ),
    ]
)
