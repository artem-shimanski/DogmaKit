//
//  PlanetaryCatalog.swift
//  DogmaPlanetary
//
//  Created by Artem Shimanski on 14.10.2026.
//

import Foundation
import FlatBin
@_exported import DogmaModels

/// Read-only planetary industry catalog over `planetary.bin`.
///
/// Unlike `TypeCatalog`/`TextCatalog`, the data is materialized whole at load rather than read from a mapped file on
/// every query: it is a few kilobytes, and the colony simulation looks up a schematic on every event.
public struct PlanetaryCatalog: Sendable {
    public typealias Schematic = DogmaPlanetaryData.Schematic
    public typealias Pin = DogmaPlanetaryData.Pin
    public typealias Commodity = DogmaPlanetaryData.Commodity
    public typealias Resources = DogmaPlanetaryData.Resources

    @usableFromInline let data: DogmaPlanetaryData

    /// A catalog from an arbitrary file (custom build, server download).
    public init(contentsOf url: URL) throws {
        self.init(data: try Data(contentsOf: url))
    }

    public init(data: Data) {
        let decoder = FlatDecoder(data: data)
        self.data = decoder.decode(DogmaPlanetaryData.self).load()
    }

    /// A catalog from the target's resources.
    public static func bundled() throws -> PlanetaryCatalog {
        guard let url = Bundle.module.url(forResource: "planetary", withExtension: "bin") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try PlanetaryCatalog(contentsOf: url)
    }

    // MARK: - Schematics

    @inlinable
    public func schematic(_ id: SchematicID) -> Schematic? {
        data.schematics[id]
    }

    /// All schematic IDs, ascending.
    public var schematicIDs: [SchematicID] {
        data.schematics.map(\.key).sorted { $0.rawValue < $1.rawValue }
    }

    /// The schematic that produces a commodity. In the SDE every P1-P4 commodity has exactly one.
    public func schematic(producing typeID: TypeID) -> Schematic? {
        data.schematics.first { $0.value.output.typeID == typeID }?.value
    }

    /// Schematics a processor of this type can run, in ascending ID order.
    public func schematics(for processorTypeID: TypeID) -> [Schematic] {
        data.schematics
            .filter { $0.value.processors.contains(processorTypeID) }
            .map(\.value)
            .sorted { $0.id.rawValue < $1.id.rawValue }
    }

    // MARK: - Pins and commodities

    @inlinable
    public func pin(_ typeID: TypeID) -> Pin? {
        data.pins[typeID]
    }

    @inlinable
    public func commodity(_ typeID: TypeID) -> Commodity? {
        data.commodities[typeID]
    }

    // MARK: - Planner

    /// Number of command center levels (6: 0...5).
    public var commandCenterLevelCount: Int {
        data.commandCenterLevels.count
    }

    /// Command center CPU/PG at an upgrade level (ESI `upgrade_level`).
    public func commandCenter(level: Int) -> Resources? {
        data.commandCenterLevels.indices.contains(level) ? data.commandCenterLevels[level] : nil
    }

    public var link: DogmaPlanetaryData.Link {
        data.link
    }

    /// Extractor formula constants (`ecuDecayFactor`/`ecuNoiseFactor`).
    public var extractor: DogmaPlanetaryData.ExtractorConstants {
        data.extractor
    }
}
