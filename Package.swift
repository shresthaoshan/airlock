// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "airlock",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure logic: advert parsing, matching your AirPods, and the lock rules.
        .target(name: "AirLockCore"),
        // The menu bar app: Bluetooth scan, System Information lookup, lock.
        .executableTarget(name: "AirLock", dependencies: ["AirLockCore"],
                          swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "AirLockCoreTests", dependencies: ["AirLockCore"]),
        .testTarget(name: "AirLockTests", dependencies: ["AirLock", "AirLockCore"],
                    swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
