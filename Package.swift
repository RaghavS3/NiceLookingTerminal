// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "NiceLookingTerminal",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.1")
    ],
    targets: [
        .target(
            name: "MyTermCore"
        ),
        .target(
            name: "MyTermTerminal",
            dependencies: [
                .target(name: "MyTermCore"),
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ]
        ),
        .target(
            name: "MyTermApp",
            dependencies: [
                .target(name: "MyTermCore"),
                .target(name: "MyTermTerminal"),
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ],
            path: "Sources/MyTerm"
        ),
        .executableTarget(
            name: "MyTerm",
            dependencies: [
                .target(name: "MyTermApp")
            ],
            path: "Sources/MyTermExecutable"
        ),
        .testTarget(
            name: "MyTermTests",
            dependencies: [
                .target(name: "MyTermCore"),
                .target(name: "MyTermTerminal"),
                .target(name: "MyTermApp"),
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ],
            resources: [
                .copy("ManualUISmokeTestChecklist.md")
            ]
        ),
    ]
)
