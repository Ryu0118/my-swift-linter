// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "my-swift-linter",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/Ryu0118/swift-ast-lint.git", from: "0.1.2"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "600.0.0" ..< "700.0.0"),
    ],
    targets: [
        .target(name: "Rules", dependencies: [
            .product(name: "SwiftASTLint", package: "swift-ast-lint"),
            .product(name: "SwiftSyntax", package: "swift-syntax"),
        ]),
        .executableTarget(
            name: "my-swift-linter",
            dependencies: ["Rules"]
        ),
        .testTarget(
            name: "RulesTests",
            dependencies: ["Rules", .product(name: "SwiftASTLintTestSupport", package: "swift-ast-lint")]
        ),
    ]
)
