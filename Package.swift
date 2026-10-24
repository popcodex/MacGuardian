// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "MacGuardian", platforms: [.macOS(.v14)], products: [.executable(name: "MacGuardian", targets: ["MacGuardian"])], targets: [.target(name: "MacGuardianCore"), .executableTarget(name: "MacGuardian", dependencies: ["MacGuardianCore"]), .testTarget(name: "MacGuardianCoreTests", dependencies: ["MacGuardianCore"])], swiftLanguageModes: [.v5])
