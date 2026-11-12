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
    targets: [
        // Thin C wrapper around the AppleSMC user client (only the LED key).
        .target(
            name: "CSMC",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        // Shared, UI-free logic: light states, IPC, Pomodoro, MCP.
        .target(name: "LambaCore"),
        // Menu bar app.
        .executableTarget(
            name: "LambaApp",
            dependencies: ["LambaCore", "CSMC"] // CSMC: read-only LED probe, no root needed
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
