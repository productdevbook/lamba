// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Lamba",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "LambaApp", targets: ["LambaApp"]),
        .executable(name: "LambaHelper", targets: ["LambaHelper"]),
        .executable(name: "lamba", targets: ["LambaCLI"]),
    ],
    dependencies: [
        // Sparkle: signed automatic updates (feed on the CDN, see scripts/release.sh).
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        // Thin C wrapper around the AppleSMC user client (LED, fans, any key).
        .target(
            name: "CSMC",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        // Shared, UI-free logic: light states, IPC, Pomodoro, MCP.
        .target(name: "LambaCore"),
        // Menu bar app.
        .executableTarget(
            name: "LambaApp",
            dependencies: ["LambaCore", "CSMC", .product(name: "Sparkle", package: "Sparkle")], // CSMC: LED probe, fan readings
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        // Root launchd daemon; the only component that touches the SMC.
        .executableTarget(
            name: "LambaHelper",
            dependencies: ["LambaCore", "CSMC"],
            linkerSettings: [.linkedFramework("SystemConfiguration")]
        ),
        // `lamba` command line tool (also hosts the MCP server).
        .executableTarget(
            name: "LambaCLI",
            dependencies: ["LambaCore"]
        ),
        .testTarget(
            name: "LambaCoreTests",
            dependencies: ["LambaCore"]
        ),
    ]
)
