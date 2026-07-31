// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "MyTerm",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.1")
    ],
    targets: [
        .executableTarget(
            name: "MyTerm",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ]
        )
    ]
)
