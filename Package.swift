// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Daycal",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "Daycal",
            targets: ["Daycal"]
        )
    ],
    dependencies: [
    ],
    targets: [
        .executableTarget(
            name: "Daycal",
            dependencies: []
        )
    ]
)
