// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexSidecar",
    platforms: [.macOS(.v14)],
    products: [.library(name: "SidecarCore", targets: ["SidecarCore"]),
               .executable(name: "CodexSidecar", targets: ["CodexSidecar"])],
    targets: [
        .target(name: "SidecarCore"),
        .executableTarget(name: "CodexSidecar", dependencies: ["SidecarCore"], exclude: ["Resources/Info.plist"]),
        .testTarget(name: "SidecarCoreTests", dependencies: ["SidecarCore"],
                    resources: [.process("Fixtures")])
    ]
)
