// swift-tools-version:5.9
import Foundation
import PackageDescription

// Embedding Info.plist in the executable lets a bare `swift run NothingXMac` use
// Bluetooth too; without the usage string macOS kills the process on first access.
let infoPlist = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Resources/Info.plist").path

let package = Package(
    name: "NothingXMac",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "NothingXMac", targets: ["NothingXMac"]),
    ],
    targets: [
        // Earbud protocol: framing, command codecs and per-model capabilities. No UI, no Bluetooth.
        .target(name: "NothingKit"),
        // The menu bar app: IOBluetooth transport, device state and SwiftUI panel.
        .executableTarget(
            name: "NothingXMac",
            dependencies: ["NothingKit"],
            linkerSettings: [
                .linkedFramework("IOBluetooth"),
                .linkedFramework("ServiceManagement"),
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", infoPlist]),
            ]
        ),
        // `swift run NothingKitChecks`: protocol self-checks (XCTest isn't available without Xcode).
        .executableTarget(name: "NothingKitChecks", dependencies: ["NothingKit"]),
    ]
)
