// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Hostpane",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Hostpane", targets: ["Hostpane"])
    ],
    dependencies: [
        .package(url: "https://github.com/GitSwiftHQ/Traversio.git", from: "1.0.8"),
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.20.0")
    ],
    targets: [
        .target(
            name: "HostpaneCore",
            dependencies: [
                .product(name: "Traversio", package: "Traversio")
            ],
            path: "Sources/HostpaneCore"
        ),
        .executableTarget(
            name: "Hostpane",
            dependencies: [
                "HostpaneCore",
                .product(name: "Traversio", package: "Traversio"),
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ],
            path: "Sources/Hostpane",
            exclude: [
                "Resources/Info.plist",
                "Resources/AppIcon-1024.png",
                "Resources/AppIcon.icns"
            ]
        ),
        .executableTarget(
            name: "HostpaneCheck",
            dependencies: ["HostpaneCore"],
            path: "Sources/HostpaneCheck"
        )
    ]
)
