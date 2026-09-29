// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MenuBarGroups",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MenuBarGroups", targets: ["MenuBarGroups"])],
    targets: [.executableTarget(name: "MenuBarGroups")]
)
