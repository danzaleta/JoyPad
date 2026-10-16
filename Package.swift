// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "JoyPad",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "JoyPadProtocol",
            targets: ["JoyPadProtocol"]
        ),
        .library(
            name: "JoyPadClientCore",
            targets: ["JoyPadClientCore"]
        ),
        .executable(
            name: "JoyPadServer",
            targets: ["JoyPadServer"]
        ),
        .executable(
            name: "JoyPadCLI",
            targets: ["JoyPadCLI"]
        )
    ],
    targets: [
        // Shared ultra-low-latency binary protocol & P2P networking layer
        .target(
            name: "JoyPadProtocol",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        // Shared iOS/multiplatform client core (views, haptics, P2P sender)
        .target(
            name: "JoyPadClientCore",
            dependencies: ["JoyPadProtocol"]
        ),
        // macOS Menu Bar Companion Server & Input Injection Engine
        .executableTarget(
            name: "JoyPadServer",
            dependencies: ["JoyPadProtocol"]
        ),
        // Interactive Test Harness CLI for macOS
        .executableTarget(
            name: "JoyPadCLI",
            dependencies: ["JoyPadProtocol"]
        ),
        // iOS SwiftUI Client Application
        .executableTarget(
            name: "JoyPadClientApp",
            dependencies: ["JoyPadClientCore"]
        ),
        // Unit tests for binary serialization and protocol integrity
        .testTarget(
            name: "JoyPadProtocolTests",
            dependencies: ["JoyPadProtocol"]
        )
    ]
)
