// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LectureStudio",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "StudioCore", targets: ["StudioCore"]),
        .executable(name: "LectureStudio", targets: ["LectureStudio"]),
    ],
    targets: [
        // Everything that knows the lecture repo: files, profile, templates, scaffolds, git, Oberik control plane.
        .target(name: "StudioCore", path: "Sources/StudioCore"),
        // The SwiftUI app. Web views host the shared JS core (Marp preview, QA, CodeMirror, Oberik SDK).
        .executableTarget(
            name: "LectureStudio",
            dependencies: ["StudioCore"],
            path: "Sources/LectureStudio",
            resources: [.copy("Resources")]
        ),
        .testTarget(name: "StudioCoreTests", dependencies: ["StudioCore"], path: "Tests/StudioCoreTests"),
    ],
    swiftLanguageModes: [.v5]
)
