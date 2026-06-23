// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "webwrap",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "webwrap", targets: ["webwrap"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.7.0")
    ],
    targets: [
        .executableTarget(
            name: "webwrap",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        )
    ]
)
