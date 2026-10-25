// swift-tools-version: 6.4

import PackageDescription
import CompilerPluginSupport

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
        .package(url: "https://github.com/artem-shimanski/FlatBin.git", .upToNextMinor(from: "0.1.0")),
        .package(url: "https://github.com/artem-shimanski/BitField.git", .upToNextMinor(from: "0.1.0")),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0")
    ],
    targets: [
        .target(
            name: "DogmaKit",
            dependencies: [
                "DogmaModels",
                "DogmaKitMacros",
                .product(name: "BitField", package: "BitField")
            ],
            resources: [.process("Resources")],
            swiftSettings: [
                .enableExperimentalFeature("Lifetimes")
            ]
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
                .product(name: "FlatBin", package: "FlatBin")
            ],
            resources: [.process("Resources")],
            swiftSettings: [
                .enableExperimentalFeature("Lifetimes")
            ]
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
