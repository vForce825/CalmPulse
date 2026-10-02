// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "WellnessServices", platforms: [.iOS("27.0"), .watchOS("27.0"), .macOS(.v15)], products: [.library(name: "WellnessServices", targets: ["WellnessServices"])], dependencies: [.package(path: "Packages/WellnessCore")], targets: [.target(name: "WellnessServices", dependencies: ["WellnessCore"], path: "Apps/Shared"), .testTarget(name: "WellnessServicesTests", dependencies: ["WellnessServices", "WellnessCore"], path: "Tests/Integration")])
