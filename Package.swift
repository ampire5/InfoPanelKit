// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "InfoPanelKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "InfoPanelModel", targets: ["InfoPanelModel"]),
        .library(name: "InfoPanelKit", targets: ["InfoPanelKit"]),
    ],
    targets: [
        .target(name: "InfoPanelModel"),
        .target(name: "InfoPanelKit", dependencies: ["InfoPanelModel"]),
        .executableTarget(name: "infopanel-demo", dependencies: ["InfoPanelKit"]),
        .testTarget(name: "InfoPanelModelTests", dependencies: ["InfoPanelModel"]),
        .testTarget(name: "InfoPanelKitTests", dependencies: ["InfoPanelKit"]),
    ],
    swiftLanguageModes: [.v5]
)
