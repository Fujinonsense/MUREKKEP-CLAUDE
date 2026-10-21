// swift-tools-version: 5.9

// Swift Playgrounds / Xcode app package.

import PackageDescription
import AppleProductTypes

let package = Package(
    name: "Murekkep",
    platforms: [
        .iOS("17.0")
    ],
    products: [
        .iOSApplication(
            name: "Murekkep",
            targets: ["AppModule"],
            bundleIdentifier: "com.murekkep.app",
            displayVersion: "3.0",
            bundleVersion: "16",
            appIcon: .asset("AppIcon"),
            supportedDeviceFamilies: [
                .pad,
                .phone
            ],
            supportedInterfaceOrientations: [
                .portrait,
                .landscapeRight,
                .landscapeLeft,
                .portraitUpsideDown(.when(deviceFamilies: [.pad]))
            ],
            // Launch screen (full native resolution) and scene settings.
            additionalInfoPlistContentFilePath: "AppInfo.plist"
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: ".",
            exclude: ["AppInfo.plist"]
        )
    ]
)
