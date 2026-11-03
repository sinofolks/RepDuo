// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "RepDuoCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "RepDuoCore", targets: ["RepDuoCore"]),
        .library(name: "RepDuoPersistence", targets: ["RepDuoPersistence"])
    ],
    targets: [
        .target(
            name: "RepDuoCore",
            path: "RepDuo/Domain"
        ),
        .testTarget(
            name: "RepDuoCoreTests",
            dependencies: ["RepDuoCore"],
            path: "RepDuoTests/Domain",
            resources: [.copy("Fixtures")]
        ),
        .target(
            name: "RepDuoPersistence",
            dependencies: ["RepDuoCore"],
            path: "RepDuo/Services/Persistence"
        ),
        .testTarget(
            name: "RepDuoPersistenceTests",
            dependencies: ["RepDuoCore", "RepDuoPersistence"],
            path: "RepDuoTests/Persistence"
        )
    ],
    swiftLanguageVersions: [.v5]
)
