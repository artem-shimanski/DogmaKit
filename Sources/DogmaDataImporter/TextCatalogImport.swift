//
//  TextCatalogImport.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 02.08.2026.
//

import Foundation
import DogmaText

/// Builds the English name catalog (`text-en.bin`) from the same tables as `sde.bin`, so it cannot contain
/// names of identifiers the engine lacks. Synthetic entries from `patch()` are included. Call AFTER `patch()`.
@MainActor
func buildTextCatalog() -> DogmaTextData {
    var text = DogmaTextData()

    // Already-typed IDs.
    text.types = PerfectDictionary(cleaned(types.idToName))
    text.attributes = PerfectDictionary(cleaned(dogmaAttributes.idToName))
    text.effects = PerfectDictionary(cleaned(dogmaEffects.idToName))
    text.warfareBuffs = PerfectDictionary(cleaned(warfareBuffs.idToName))

    // Raw SDE tables keyed by `Int`.
    text.groups = PerfectDictionary(remapped(groups.idToName, as: GroupID.self))
    text.categories = PerfectDictionary(remapped(categories.idToName, as: CategoryID.self))
    text.metaGroups = PerfectDictionary(remapped(metaGroups.idToName, as: MetaGroupID.self))
    text.units = PerfectDictionary(remapped(units.idToName, as: UnitID.self))
    text.attributeCategories = PerfectDictionary(remapped(dogmaAttributeCategories.idToName,
                                                          as: AttributeCategoryID.self))
    // PI schematic names (`name.en`).
    text.schematics = PerfectDictionary(remapped(planetSchematics.idToName, as: SchematicID.self))

    return text
}

/// Drops empty names: they would occupy an entry in `PerfectDictionary` and read the same as `nil`.
private func cleaned<ID: Hashable>(_ idToName: [ID: String]) -> [ID: String] {
    var result: [ID: String] = [:]
    result.reserveCapacity(idToName.count)
    for (id, name) in idToName {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { continue }
        result[id] = name
    }
    return result
}

private func remapped<ID: RawRepresentable & Hashable>(_ idToName: [Int: String],
                                                       as type: ID.Type) -> [ID: String]
where ID.RawValue: FixedWidthInteger {
    var result: [ID: String] = [:]
    result.reserveCapacity(idToName.count)
    for (id, name) in idToName {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              let rawValue = ID.RawValue(exactly: id),
              let id = ID(rawValue: rawValue) else { continue }
        result[id] = name
    }
    return result
}
