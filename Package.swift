// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "FaceUnlock",
    platforms: [
        .macOS("26.0")
    ],
    targets: [
        // Pure, UI-free logic. Unit-testable without a camera or permissions.
        // Kept in Swift 6 language mode: it is all value types and simple math,
        // so strict concurrency costs nothing here.
        .target(
            name: "FaceUnlockCore"
        ),
        // Camera, Vision, and Core ML. Depends on Core for the math and stores.
        // AVFoundation's capture delegate and Vision's handlers predate strict
        // concurrency, so this target builds in Swift 5 mode to stay readable.
        .target(
            name: "FaceUnlockVision",
            dependencies: ["FaceUnlockCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // The menu-bar app: AppKit lifecycle, SwiftUI enrollment, settings.
        .executableTarget(
            name: "FaceUnlock",
            dependencies: ["FaceUnlockCore", "FaceUnlockVision"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "FaceUnlockCoreTests",
            dependencies: ["FaceUnlockCore"]
        ),
    ]
)
