// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "VoltCore",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "Volt", targets: ["Volt"]),
    ],
    targets: [
        .target(
            name: "Volt",
            path: "Volt",
            exclude: [
                "Assets.xcassets",
                "ContentView.swift",
                "Info.plist",
                "Services/CredentialStore.swift",
                "ViewModels",
                "Views",
                "Volt.entitlements",
                "VoltApp.swift",
            ],
            sources: [
                "Models/CredentialModels.swift",
                "Models/UsageModels.swift",
                "Services/ClaudeUsageService.swift",
                "Services/OpenAIUsageService.swift",
            ]
        ),
        .testTarget(
            name: "VoltTests",
            dependencies: ["Volt"],
            path: "VoltTests",
            resources: [
                .copy("Fixtures"),
            ]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
