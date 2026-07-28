// swift-tools-version: 6.0
//
// Intended production deps (both blocked in this environment as of 2026-07-28):
//   - pointfreeco/swift-composable-architecture >= 1.19
//       → `swift package resolve` fails cloning GitHub (empty reply / 443)
//   - MrKai77/Luminare >= 0.2
//       → resolves from SPM cache, but `swift build` fails without full Xcode
//         SwiftUIMacros (`@Entry` / Preview macros). Command Line Tools only.
//
// Ship path: scripts/build_app.sh → swiftc over Sources/** with in-repo MiniTCA
// + hand-rolled AppChrome (Luminare-aligned tokens). Swap when Xcode + GitHub
// fetch are available, then `swift build -c release`.
import PackageDescription

let package = Package(
    name: "MorningBrief",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MorningBrief", targets: ["MorningBrief"]),
    ],
    targets: [
        .executableTarget(
            name: "MorningBrief",
            path: "Sources"
        ),
    ]
)
