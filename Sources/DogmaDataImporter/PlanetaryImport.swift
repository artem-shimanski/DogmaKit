//
//  PlanetaryImport.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 14.10.2026.
//

import Foundation
import DogmaPlanetary

/// PI schematics as stored in the SDE. Separate from `buildPlanetaryData` because their names also feed `SchematicID` and the name catalog.
func loadPlanetSchematics(from sde: URL) async throws -> Table<PlanetSchematicInfo> {
    try await Table<PlanetSchematicInfo>(contentsOf: sde.appending(path: "planetSchematics.jsonl"), id: \._key)
        .indexed(by: \.name.en)
}

/// Builds `planetary.bin`.
///
/// Reads the SDE itself rather than using the engine's filtered tables: the command center level table comes from
/// UNPUBLISHED legacy types, which `rawTypes` in `main.swift` has already dropped.
/// Anything unexpected (a schematic without exactly one output, differing resources at one command center level,
/// no `Link` type) is a `precondition` failure: a silently malformed file is worse than a failed import.
func buildPlanetaryData(from sde: URL, schematics rawSchematics: Table<PlanetSchematicInfo>) async throws -> DogmaPlanetaryData {
    let groupIDs = Set(PinGroup.allCases.map(\.rawValue) + [linkGroupID])
        .union(commodityGroups.keys)
    let types = try await Table<TypeInfo>(contentsOf: sde.appending(path: "types.jsonl"), id: \._key)
        .filter { groupIDs.contains($0.value.groupID) }
    let dogma = try await Table<TypeDogmaInfo>(contentsOf: sde.appending(path: "typeDogma.jsonl"), id: \._key)
        .filter { types[$0.key] != nil }
    let attributes = try await Table<DogmaAttributeInfo>(contentsOf: sde.appending(path: "dogmaAttributes.jsonl"), id: \._key)
        .indexed(by: \.name)

    func attributeID(_ name: String) -> Int {
        guard let id = attributes.index(of: name) else { preconditionFailure("attribute \(name) is missing in SDE") }
        return id
    }

    /// Type attributes looked up by NAME, so `cpuLoad` (49) cannot be confused with `cpuOutput` (48).
    func values(of typeID: Int) -> [Int: Double] {
        Dictionary(dogma[typeID]?.dogmaAttributes.map { ($0.attributeID, $0.value) } ?? [],
                   uniquingKeysWith: { a, _ in a })
    }
    func value(_ name: String, of typeID: Int) -> Double {
        values(of: typeID)[attributeID(name)] ?? 0
    }

    var data = DogmaPlanetaryData()

    // Commodities: tier from the group, volume from types.jsonl.
    var commodities: [TypeID: DogmaPlanetaryData.Commodity] = [:]
    for (id, type) in types.elements {
        guard let tier = commodityGroups[type.groupID], type.published else { continue }
        guard let volume = type.volume, volume > 0 else { preconditionFailure("commodity \(id) has no volume") }
        commodities[TypeID(rawValue: UInt32(id))] = .init(tier: tier, volume: volume)
    }
    data.commodities = PerfectDictionary(commodities)

    // Schematics.
    var schematics: [SchematicID: DogmaPlanetaryData.Schematic] = [:]
    for (id, info) in rawSchematics.elements {
        let outputs = info.types.filter { !$0.isInput }
        precondition(outputs.count == 1, "schematic \(id) has \(outputs.count) outputs")
        func amount(_ type: PlanetSchematicInfo.TypesInfo) -> DogmaPlanetaryData.Amount {
            let typeID = TypeID(rawValue: UInt32(type._key))
            precondition(commodities[typeID] != nil, "schematic \(id) references unknown commodity \(type._key)")
            precondition(type.quantity > 0, "schematic \(id): zero quantity of \(type._key)")
            return .init(typeID: typeID, quantity: UInt32(type.quantity))
        }
        let inputs = info.types.filter(\.isInput).map(amount).sorted { $0.typeID.rawValue < $1.typeID.rawValue }
        precondition(!inputs.isEmpty, "schematic \(id) has no inputs")
        precondition(info.cycleTime > 0, "schematic \(id) has no cycle time")
        let processors = info.pins.map { TypeID(rawValue: UInt32($0)) }.sorted { $0.rawValue < $1.rawValue }
        let schematicID = SchematicID(rawValue: UInt16(id))
        schematics[schematicID] = .init(id: schematicID,
                                        cycleTime: UInt32(info.cycleTime),
                                        output: amount(outputs[0]),
                                        inputs: inputs,
                                        processors: processors)
    }
    data.schematics = PerfectDictionary(schematics)

    // Pins: published only; legacy command centers go into the level table below.
    var pins: [TypeID: DogmaPlanetaryData.Pin] = [:]
    for (id, type) in types.elements {
        guard let group = PinGroup(rawValue: type.groupID), type.published else { continue }
        let planet = value("planetRestriction", of: id)
        precondition(planet > 0, "pin \(id) has no planetRestriction")
        pins[TypeID(rawValue: UInt32(id))] = .init(
            kind: group.kind,
            planetTypeID: TypeID(rawValue: UInt32(planet)),
            capacity: type.capacity ?? 0,
            cpuLoad: value("cpuLoad", of: id),
            powerLoad: value("powerLoad", of: id),
            cpuOutput: value("cpuOutput", of: id),
            powerOutput: value("powerOutput", of: id),
            extractorHeadCPU: value("ecuExtractorHeadCPU", of: id),
            extractorHeadPower: value("ecuExtractorHeadPower", of: id))
    }
    data.pins = PerfectDictionary(pins)

    // Command center levels: the legacy types' `metaLevel` (a types.jsonl field, not the attribute of the same
    // name, which is `metaLevelOld`) is the upgrade level; published types have 0. Values must match across
    // planets, which is verified.
    var levels: [Int: DogmaPlanetaryData.Resources] = [:]
    for (id, type) in types.elements where type.groupID == PinGroup.commandCenters.rawValue {
        guard let level = type.metaLevel else { preconditionFailure("command center \(id) has no metaLevel") }
        let resources = DogmaPlanetaryData.Resources(cpu: value("cpuOutput", of: id), power: value("powerOutput", of: id))
        if let existing = levels[level] {
            precondition(existing == resources, "command center level \(level): \(existing) vs \(resources) (type \(id))")
        }
        levels[level] = resources
    }
    precondition(Set(levels.keys) == Set(0..<levels.count), "command center levels are not contiguous: \(levels.keys.sorted())")
    data.commandCenterLevels = (0..<levels.count).map { levels[$0]! }

    // The only type in the Planetary Links group.
    let links = types.elements.filter { $0.value.groupID == linkGroupID }
    precondition(links.count == 1, "expected exactly one Link type, found \(links.count)")
    let link = links.first!.key
    data.link = .init(cpuLoad: value("cpuLoad", of: link),
                      powerLoad: value("powerLoad", of: link),
                      cpuLoadPerKm: value("cpuLoadPerKm", of: link),
                      powerLoadPerKm: value("powerLoadPerKm", of: link),
                      cpuLoadLevelModifier: value("cpuLoadLevelModifier", of: link),
                      powerLoadLevelModifier: value("powerLoadLevelModifier", of: link),
                      logisticalCapacity: value("logisticalCapacity", of: link))

    // Formula constants are attribute default values; no type assigns them.
    data.extractor = .init(decayFactor: attributes[attributeID("ecuDecayFactor")]!.defaultValue,
                           noiseFactor: attributes[attributeID("ecuNoiseFactor")]!.defaultValue)

    return data
}

/// Pin groups (category 41); legacy extractors (1026) are excluded.
private enum PinGroup: Int, CaseIterable {
    case commandCenters = 1027
    case processors = 1028
    case storageFacilities = 1029
    case spaceports = 1030
    case extractorControlUnits = 1063

    var kind: DogmaPlanetaryData.PinKind {
        switch self {
        case .commandCenters: .commandCenter
        case .processors: .processor
        case .storageFacilities: .storage
        case .spaceports: .launchpad
        case .extractorControlUnits: .extractor
        }
    }
}

private let linkGroupID = 1036

/// Commodity groups mapped to tiers. Explicit, because raw resources have no tier in the group name.
private let commodityGroups: [Int: DogmaPlanetaryData.Tier] = [
    1032: .p0,  // Planet Solid - Raw Resource
    1033: .p0,  // Planet Liquid-Gas - Raw Resource
    1035: .p0,  // Planet Organic - Raw Resource
    1042: .p1,  // Basic Commodities - Tier 1
    1034: .p2,  // Refined Commodities - Tier 2
    1040: .p3,  // Specialized Commodities - Tier 3
    1041: .p4,  // Advanced Commodities - Tier 4
]
