// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Vimshot",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "vimshot", targets: ["Vimshot"])
    ],
    targets: [
        .executableTarget(name: "Vimshot")
    ]
)
