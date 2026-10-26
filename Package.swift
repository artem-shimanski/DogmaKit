// swift-tools-version: 6.4

import PackageDescription
import CompilerPluginSupport

/// Every platform but WebAssembly, which has no `Bundle`: resource targets are linked only on these.
let platformsWithBundle: [Platform] = [
    .macOS, .macCatalyst, .iOS, .tvOS, .watchOS, .visionOS, .driverKit, .linux, .windows, .android, .openbsd
]

let package = Package(
    name: "DogmaKit",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(
            name: "DogmaKit",
            targets: ["DogmaKit"]
        ),
        .library(
            name: "DogmaKitIO",
            targets: ["DogmaKitIO"]
        ),
        // SDE names. A separate product: the engine does not need them.
        .library(
            name: "DogmaText",
            targets: ["DogmaText"]
        ),
        // Planetary industry: `planetary.bin` data and colony simulation. Independent of `DogmaKit`.
        .library(
            name: "DogmaPlanetary",
            targets: ["DogmaPlanetary"]
        ),
        .library(
            name: "DogmaIDs",
            targets: ["DogmaIDs"]
        ),
        .plugin(name: "SDESchemaGeneratorPlugin", targets: ["SDESchemaGeneratorPlugin"])
    ],
    dependencies: [
        .package(url: "https://github.com/artem-shimanski/FlatBin.git", .upToNextMinor(from: "0.1.2")),
        .package(url: "https://github.com/artem-shimanski/BitField.git", .upToNextMinor(from: "0.1.2")),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "603.0.0"..<"605.0.0")
    ],
    targets: [
        .target(
            name: "DogmaKit",
            dependencies: [
                "DogmaModels",
                "DogmaKitMacros",
                .target(name: "DogmaKitResources", condition: .when(platforms: platformsWithBundle)),
                .product(name: "BitField", package: "BitField")
            ],
            swiftSettings: [
                .enableExperimentalFeature("Lifetimes")
            ]
        ),
        // `sde.bin`. Outside `DogmaKit` so WebAssembly builds can leave out `Bundle` and full Foundation.
        .target(
            name: "DogmaKitResources",
            resources: [.process("Resources")]
        ),
        // `@Snapshottable`: generates `FitStats` node snapshots. Internal to `DogmaKit`.
        .macro(
            name: "DogmaKitMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax")
            ]
        ),
        .target(name: "DogmaIDs"),
        .target(
            name: "DogmaModels",
            dependencies: [
                "DogmaIDs",
                .product(name: "FlatBin", package: "FlatBin"),
                .product(name: "BitField", package: "BitField")
            ],
            swiftSettings: [
                .enableExperimentalFeature("LifetimeDependence"),
                .enableExperimentalFeature("Lifetimes")
            ]
        ),
        // Importers for public fit formats (EFT / DNA / in-game XML).
        .target(
            name: "DogmaKitIO",
            dependencies: ["DogmaKit"]
        ),
        // Name catalog (`text-en.bin`). Independent of `DogmaKit`.
        .target(
            name: "DogmaText",
            dependencies: [
                "DogmaModels",
                .target(name: "DogmaTextResources", condition: .when(platforms: platformsWithBundle)),
                .product(name: "FlatBin", package: "FlatBin")
            ],
            swiftSettings: [
                .enableExperimentalFeature("Lifetimes")
            ]
        ),
        // `text-en.bin`, split off for the same reason as `DogmaKitResources`.
        .target(
            name: "DogmaTextResources",
            resources: [.process("Resources")]
        ),
        // Planetary industry (`planetary.bin`). Structured like `DogmaText`.
        .target(
            name: "DogmaPlanetary",
            dependencies: [
                "DogmaModels",
                .product(name: "FlatBin", package: "FlatBin")
            ],
            resources: [.process("Resources")],
            swiftSettings: [
                .enableExperimentalFeature("Lifetimes")
            ]
        ),
        .testTarget(
            name: "DogmaPlanetaryTests",
            dependencies: ["DogmaPlanetary", "DogmaText"]
        ),
        .testTarget(
            name: "DogmaKitTests",
            dependencies: ["DogmaKit", "DogmaText"]
        ),
        .testTarget(
            name: "DogmaKitMacrosTests",
            dependencies: [
                "DogmaKitMacros",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax")
            ]
        ),
        .testTarget(
            name: "DogmaKitIOTests",
            dependencies: ["DogmaKitIO", "DogmaKit", "DogmaText"]
        ),
        .executableTarget(
            name: "DogmaDataImporter",
            dependencies: ["DogmaModels", "DogmaText", "DogmaPlanetary"]
        ),
        .plugin(
            name: "DogmaDataImporterPlugin",
            capability: .command(intent: .custom(verb: "sde-import", description: "Import SDE Data"),
                                 permissions: [.writeToPackageDirectory(reason: "This plugin need to update source code")]),
            dependencies: ["DogmaDataImporter"]
        ),
        .executableTarget(
            name: "SDESchemaGenerator"
        ),
        .plugin(
            name: "SDESchemaGeneratorPlugin",
            capability: .command(intent: .custom(verb: "generate-schema", description: "Generate SDE Schemes"),
                                 permissions: [.writeToPackageDirectory(reason: "This plugin need to update source code")]),
            dependencies: ["SDESchemaGenerator"]
        )
    ],
    swiftLanguageModes: [.v6]
)
