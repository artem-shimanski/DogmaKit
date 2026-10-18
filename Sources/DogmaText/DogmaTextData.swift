//
//  DogmaTextData.swift
//  DogmaText
//
//  Created by Artem Shimanski on 02.08.2026.
//

import FlatBin
import DogmaModels

/// Flat schema of the name catalog, stored separately from `sde.bin` (`text-en.bin`) because the engine never needs names.
///
/// Types, groups, categories and meta groups use the localized `name.en`. Attributes, effects and units use the
/// internal SDE name (`cpu`, `Length`), which matches the generated `AttributeID`/`EffectID` constants. Warfare buffs
/// use `developerDescription`, as for `WarfareBuffID`.
@FlatCodable
public struct DogmaTextData: Sendable {
    public var types: PerfectDictionary<TypeID, String> = [:]
    public var groups: PerfectDictionary<GroupID, String> = [:]
    public var categories: PerfectDictionary<CategoryID, String> = [:]
    public var metaGroups: PerfectDictionary<MetaGroupID, String> = [:]
    public var attributes: PerfectDictionary<AttributeID, String> = [:]
    public var attributeCategories: PerfectDictionary<AttributeCategoryID, String> = [:]
    public var effects: PerfectDictionary<EffectID, String> = [:]
    public var warfareBuffs: PerfectDictionary<WarfareBuffID, String> = [:]
    public var units: PerfectDictionary<UnitID, String> = [:]
    /// PI schematics: `name.en`.
    public var schematics: PerfectDictionary<SchematicID, String> = [:]

    public init() {}
}
