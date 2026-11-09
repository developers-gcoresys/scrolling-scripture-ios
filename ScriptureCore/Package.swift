// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ScriptureCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "ScriptureCore", targets: ["ScriptureCore"])
    ],
    targets: [
        .target(name: "ScriptureCore"),
        .executableTarget(name: "CoreChecks", dependencies: ["ScriptureCore"], path: "Checks"),
        .testTarget(name: "ScriptureCoreTests", dependencies: ["ScriptureCore"])
    ]
)
