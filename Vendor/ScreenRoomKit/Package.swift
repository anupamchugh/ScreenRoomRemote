// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "ScreenRoomKit", platforms: [.macOS("27.0"), .iOS("27.0")], products: [.library(name: "ScreenRoomKit", targets: ["ScreenRoomKit"])], targets: [.target(name: "ScreenRoomKit")])
