// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "mailer",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "MailerCore", targets: ["MailerCore"]),
        .executable(name: "mailer", targets: ["MailerCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0")
    ],
    targets: [
        .target(name: "MailerCore"),
        .executableTarget(
            name: "MailerCLI",
            dependencies: [
                "MailerCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(name: "MailerCoreTests", dependencies: ["MailerCore"]),
    ]
)
