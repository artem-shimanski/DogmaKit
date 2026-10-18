//
//  main.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 09.04.2026.
//

import Foundation
@_exported import DogmaModels
import FlatBin

let args = CommandLine.arguments
guard args.count == 5 else { exit(1) }

let inputDir = URL(filePath: args[1])
let outputDir = URL(filePath: args[2])
/// Output directory of the `DogmaText` target.
let textOutputDir = URL(filePath: args[3])
/// Output directory of the `DogmaPlanetary` target.
let planetaryOutputDir = URL(filePath: args[4])

let sde = inputDir

let version = try await Table<_sdeInfo>(contentsOf: sde.appending(path: "_sde.jsonl"), id: \._key).elements.values.first!

let validCategoryIDs: IndexSet = [1, 2, 8, 17, 18, 20, 7, 6, 16, 23, 32, 41, 42, 43, 65, 66, 87]

var dogmaAttributes = try await Table<DogmaAttributeInfo>(contentsOf: sde.appending(path: "dogmaAttributes.jsonl"), id: \._key).indexed(by: \.name).map{DogmaSDE.AttributeInfo($0)}

let requiredSkillsAttributeIDs = Set(dogmaAttributes.nameToID.filter{
    $0.key.hasPrefix("requiredSkill") && !$0.key.hasSuffix("Level")
}.values)

let canFitShipGroupAttributesIDs = Set(dogmaAttributes.nameToID.filter{
    $0.key.hasPrefix("canFitShipGroup")
}.values)

let canFitShipTypeAttributesIDs = Set(dogmaAttributes.nameToID.filter{
    $0.key.hasPrefix("canFitShipType") || $0.key == "fitsToShipType"
}.values)

let chargeGroupAttributesIDs = Set(dogmaAttributes.nameToID.filter{
    $0.key.hasPrefix("chargeGroup")
}.values)
let chargeSizeID = dogmaAttributes.nameToID["chargeSize"]!

let dogmaAttributeCategories = try await Table<DogmaAttributeCategoryInfo>(contentsOf: sde.appending(path: "dogmaAttributeCategories.jsonl"), id: \._key).indexed(by: \.name)

let categories = try await Table<CategoryInfo>(contentsOf: sde.appending(path: "categories.jsonl"), id: \._key).indexed(by: \.name.en)
    .filter{validCategoryIDs.contains($0.key)}
let groups = try await Table<GroupInfo>(contentsOf: sde.appending(path: "groups.jsonl"), id: \._key).indexed(by: \.name.en)
    .filter{
        guard let category = categories[$0.value.categoryID] else {return false}
        if category.name.en == "Celestial" {
            // Only the environment groups; planets, moons and suns are not needed.
            return environmentGroupNames.contains($0.value.name.en)
        }
        else if category.name.en == "Commodity" {
            return $0.value.name.en == "Mutaplasmids"
        }
        else {
            return true
        }
    }
let metaGroups = try await Table<MetaGroupInfo>(contentsOf: sde.appending(path: "metaGroups.jsonl"), id: \._key).indexed(by: \.name.en)
let units = try await Table<DogmaUnitInfo>(contentsOf: sde.appending(path: "dogmaUnits.jsonl"), id: \._key).indexed(by: \.name)

let allTypesDogma = try await Table<TypeDogmaInfo>(contentsOf: sde.appending(path: "typeDogma.jsonl"), id: \._key)

// Import rule: everything the engine can compute, not only what is on the market (`published` does not mean
// "exists in game"; e.g. Civilian Data Analyzer and officer "Modified" modules are unpublished but appear in fits).
// Skills are the exception: `Pilots.add` grants ALL skills in `db.skills`, so an unpublished skill with bonuses
// would silently change every fit.
let rawTypes = try await Table<TypeInfo>(contentsOf: sde.appending(path: "types.jsonl"), id: \._key).indexed(by: \.name.en)
    .filter{
        guard let group = groups[$0.value.groupID] else {return false}
        if $0.value.published || group.name.en == "Ship Modifiers" || group.name.en == "Character" {
            return true
        }
        return categories[group.categoryID]?.name.en != "Skill" && allTypesDogma[$0.key] != nil
    }

let typesDogma = allTypesDogma
    .filter{rawTypes[$0.key] != nil}

let usedEffectIDs = IndexSet(typesDogma.elements.values.flatMap{$0.dogmaEffects?.map{$0.effectID} ?? []})
var dogmaEffects = try await Table<DogmaEffectInfo>(contentsOf: sde.appending(path: "dogmaEffects.jsonl"), id: \._key)
    .filter{usedEffectIDs.contains($0.key)}
    .indexed(by: \.name)
    .map{DogmaSDE.Effect($0)}

var warfareBuffs = Table<DogmaSDE.WarfareBuff>()

var types = rawTypes.map{DogmaSDE.TypeInfo($0)}

let filteredTypeIDs = Set(types.elements.keys)
let dynamicItemAttributes = try await Table<DynamicItemAttributeInfo>(contentsOf: sde.appending(path: "dynamicItemAttributes.jsonl"), id: \._key)
    .map{DogmaSDE.Mutaplasmid($0, filteredTypeIDs: filteredTypeIDs)}

let buffAttributeIDs = Set(dogmaAttributes.nameToID.filter{$0.key.hasPrefix("warfareBuff") && $0.key.hasSuffix("ID")}.map{$0.value})

var buffs: [Int: [String]] = [:]


for (typeID, type) in types.elements {
    let typeName = types.idToName[typeID]!
    for attributeID in buffAttributeIDs {
        guard let value = type.attributes[attributeID], value > 0 else {continue}
        let buffID = Int(value)
        buffs[buffID, default: []].append(typeName.toCamelCase())
    }
}

// Warfare buffs are imported in full: the table is small, and the sources of environment buffs
// are filtered out (Celestial category), so filtering by reference is not possible.
// Must come after types/groups/dogmaAttributes: init resolves groups and skills through them.
warfareBuffs = try await Table<DbuffCollectionInfo>(contentsOf: sde.appending(path: "dbuffCollections.jsonl"), id: \._key)
    .indexed(by: \.buffName)
    .map{DogmaSDE.WarfareBuff($0)}

for (buffID, typeNames) in buffs.sorted(by: {$0.key < $1.key}) {
    guard warfareBuffs[WarfareBuffID(rawValue: UInt16(buffID))] == nil else {continue}
    print("warning: warfare buff \(buffID) referenced by \(typeNames.joined(separator: ", ")) is missing in dbuffCollections")
}

patch()

for key in dogmaEffects.elements.keys {
    dogmaEffects.elements[key]!.modifiers.sort{$0.operation.rawValue < $1.operation.rawValue}
}

for (id, type) in types.elements {
    types.elements[id]!.effects = type.effects.map{dogmaEffects[$0.id]!}
}




let skillCategory = CategoryID(rawValue: UInt16(categories.nameToID["Skill"]!))
let skills = types.elements.filter{$0.value.categoryID == skillCategory}.map{$0.key}.sorted{$0.rawValue < $1.rawValue}


try? FileManager.default.createDirectory(at: outputDir.appending(path: "Generated"), withIntermediateDirectories: false)

try typeExtension(from: dogmaAttributes.nameToID)
    .write(to: outputDir.appending(path: "Generated/AttributeIDs.swift"), atomically: true, encoding: .utf8)
try typeExtension(of: AttributeCategoryID.self, from: dogmaAttributeCategories.nameToID)
    .write(to: outputDir.appending(path: "Generated/AttributeCategoryIDs.swift"), atomically: true, encoding: .utf8)
try typeExtension(from: dogmaEffects.nameToID)
    .write(to: outputDir.appending(path: "Generated/EffectIDs.swift"), atomically: true, encoding: .utf8)
try typeExtension(from: warfareBuffs.nameToID)
    .write(to: outputDir.appending(path: "Generated/WarfareBuffIDs.swift"), atomically: true, encoding: .utf8)
try typeExtension(from: types.nameToID, preferred: { rawTypes[Int($0.rawValue)]?.published == true })
    .write(to: outputDir.appending(path: "Generated/TypeIDs.swift"), atomically: true, encoding: .utf8)
try typeExtension(of: GroupID.self, from: groups.nameToID)
    .write(to: outputDir.appending(path: "Generated/GroupIDs.swift"), atomically: true, encoding: .utf8)
try typeExtension(of: CategoryID.self, from: categories.nameToID)
    .write(to: outputDir.appending(path: "Generated/CategoryIDs.swift"), atomically: true, encoding: .utf8)
try typeExtension(of: UnitID.self, from: units.nameToID)
    .write(to: outputDir.appending(path: "Generated/UnitIDs.swift"), atomically: true, encoding: .utf8)


// Planetary industry. Schematics load before the name catalog: their names feed both `SchematicID` and `text-en.bin`.
let planetSchematics = try await loadPlanetSchematics(from: sde)
try? FileManager.default.createDirectory(at: planetaryOutputDir.appending(path: "Generated"), withIntermediateDirectories: true)
try? FileManager.default.createDirectory(at: planetaryOutputDir.appending(path: "Resources"), withIntermediateDirectories: true)
try typeExtension(of: SchematicID.self, from: planetSchematics.nameToID)
    .write(to: planetaryOutputDir.appending(path: "Generated/SchematicIDs.swift"), atomically: true, encoding: .utf8)
try FlatEncoder.encode(try await buildPlanetaryData(from: sde, schematics: planetSchematics))
    .write(to: planetaryOutputDir.appending(path: "Resources/planetary.bin"))

// Name catalog, built from the same tables as `db`; must run after `patch()`.
try? FileManager.default.createDirectory(at: textOutputDir.appending(path: "Resources"), withIntermediateDirectories: true)
try FlatEncoder.encode(buildTextCatalog()).write(to: textOutputDir.appending(path: "Resources/text-en.bin"))

var db = DogmaSDE()
db.attributes = PerfectDictionary(dogmaAttributes.elements)
db.types = PerfectDictionary(types.elements)
db.warfareBuffs = PerfectDictionary(warfareBuffs.elements)
db.skills = skills
db.mutaplasmids = PerfectDictionary(dynamicItemAttributes.elements)

try FlatEncoder.encode(db).write(to: outputDir.appending(path: "Resources/sde.bin"))
