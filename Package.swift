// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "GraphQLWS",
    platforms: [.macOS(.v10_15)],
    products: [
        .library(
            name: "GraphQLWS",
            targets: ["GraphQLWS"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/GraphQLSwift/Graphiti.git", from: "3.0.0"),
        .package(url: "https://github.com/GraphQLSwift/GraphQL.git", from: "4.0.0"),
    ],
    targets: [
        .target(
            name: "GraphQLWS",
            dependencies: [
                .product(name: "Graphiti", package: "Graphiti"),
                .product(name: "GraphQL", package: "GraphQL"),
            ]
        ),
        .testTarget(
            name: "GraphQLWSTests",
            dependencies: ["GraphQLWS"]
        ),
    ]
)
