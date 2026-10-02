// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "WellnessCore", platforms: [.iOS("27.0"), .watchOS("27.0"), .macOS(.v15)], products: [.library(name: "WellnessCore", targets: ["WellnessCore"])], targets: [.target(name: "WellnessCore"), .testTarget(name: "WellnessCoreTests", dependencies: ["WellnessCore"])])
