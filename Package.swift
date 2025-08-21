// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "NodeMobile",
    platforms: [.iOS(.v17), .tvOS(.v17)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "NodeMobile",
            targets: ["NodeMobile"]),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .binaryTarget(name: "NodeMobile", url: "https://cdn.9228.eu/NodeMobile.xcframework.zip", checksum: "777eee8241feaba9b15b6cb7919c2f13d767e663f33c569f71a19803bcc8ca0e"),
    ]
)
