// swift-tools-version: 5.9
import PackageDescription
import Foundation

let taglibRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(".build/taglib").path

let package = Package(
    name: "StillMusic",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "StillMusic", targets: ["StillMusic"])],
    targets: [
        .target(name: "StillTagBridge",
                cxxSettings: [.unsafeFlags(["-I" + taglibRoot + "/include/taglib"])],
                linkerSettings: [.unsafeFlags(["-L" + taglibRoot + "/lib"]), .linkedLibrary("tag"), .linkedLibrary("z"), .linkedLibrary("c++")]),
        .target(name: "StillCore", dependencies: ["StillTagBridge"]),
        .executableTarget(name: "StillMusic", dependencies: ["StillCore"], path: "Sources/Still"),
        .executableTarget(name: "StillChecks", dependencies: ["StillCore"], path: "Tests/StillCoreTests")
    ],
    cxxLanguageStandard: .cxx17
)
