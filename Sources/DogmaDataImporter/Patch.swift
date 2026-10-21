//
//  Patch.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 28.04.2026.
//

import Foundation

let extraEffectID: UInt16 = 20000
@MainActor
let extraAttributeID: UInt16 = dogmaAttributes.elements.keys.map{$0.rawValue}.max()! + 1

@MainActor
func patchMissilesDamage() {
    dogmaEffects.append("characterDamageMissiles", .init(id: .init(rawValue: extraEffectID), category: .passive, modifiers: [
        .ownerRequiredSkill(.pilot, "Missile Launcher Operation", "emDamage", .postMul, "missileDamageMultiplier"),
        .ownerRequiredSkill(.pilot, "Missile Launcher Operation", "explosiveDamage", .postMul, "missileDamageMultiplier"),
        .ownerRequiredSkill(.pilot, "Missile Launcher Operation", "kineticDamage", .postMul, "missileDamageMultiplier"),
        .ownerRequiredSkill(.pilot, "Missile Launcher Operation", "thermalDamage", .postMul, "missileDamageMultiplier"),
    ]))
    types.addEffect("characterDamageMissiles", toGroup: "Character")
    
    // Damage-reduction exponent. Ammunition already carries the folded value in
    // `aoeDamageReductionFactor` (sensitivity is never populated); fighters carry a
    // factor/sensitivity pair, folded here so the runtime does not need logarithms.
    patchDamageReductionExponent(factor: "fighterAbilityAttackMissileReductionFactor",
                                 sensitivity: "fighterAbilityAttackMissileReductionSensitivity",
                                 exponent: "fighterAbilityAttackMissileReductionExponent",
                                 id: extraAttributeID + 2)
    patchDamageReductionExponent(factor: "fighterAbilityMissilesDamageReductionFactor",
                                 sensitivity: "fighterAbilityMissilesDamageReductionSensitivity",
                                 exponent: "fighterAbilityMissilesDamageReductionExponent",
                                 id: extraAttributeID + 3)
}

/// Folds a `factor`/`sensitivity` pair into one synthetic exponent attribute, `ln(drf)/ln(drs)`.
/// Types with a missing or degenerate pair (0/0, drs == 1) get no attribute, meaning "no speed correction".
@MainActor
func patchDamageReductionExponent(factor: String, sensitivity: String, exponent: String, id: UInt16) {
    let exponentID = AttributeID(rawValue: id)

    dogmaAttributes.append(exponent, .init(id: exponentID, category: 7, minAttributeID: 0, maxAttributeID: 0, defaultValue: 0, unit: 0, options: [.isStackable, .highIsGood]))

    let factorID = dogmaAttributes.nameToID[factor]!
    let sensitivityID = dogmaAttributes.nameToID[sensitivity]!

    for typeID in types.elements.keys {
        types.update(typeID) { type in
            guard let drf = type.attributes[factorID], let drs = type.attributes[sensitivityID],
                  drf > 0, drs > 0, drs != 1 else { return }
            type.attributes[exponentID] = log(drf) / log(drs)
        }
    }
}

/// Tactical modes (group "Ship Modifiers") have no slot effect, no fitting restriction and their
/// hulls have no `tacticalModes` slot in the SDE. The only link between a mode and its hull is the
/// name: "Anhinga Primary Mode" belongs to "Anhinga" (the last two words dropped). A mode whose hull
/// cannot be resolved fails the import, so a new hull is never silently left without modes.
@MainActor
func patchTacticalModes() {
    dogmaEffects.append("tacticalMode", .init(id: .init(rawValue: extraEffectID + 2), category: .passive))
    dogmaAttributes.append("tacticalModes", .init(id: .init(rawValue: extraAttributeID), category: 4, minAttributeID: 0, maxAttributeID: 0, defaultValue: 0, unit: 122, options: [.isStackable, .highIsGood]))

    guard let modeGroupID = groups.nameToID["Ship Modifiers"],
          let shipCategoryID = categories.nameToID["Ship"] else {
        fatalError("Tactical modes: group \"Ship Modifiers\" or category \"Ship\" is missing")
    }
    let shipCategory = CategoryID(rawValue: UInt16(shipCategoryID))

    // Lowest ID wins on a name collision, as everywhere in the importer.
    var hulls: [String: TypeID] = [:]
    for (typeID, type) in types.elements where type.categoryID == shipCategory {
        guard let name = types.idToName[typeID] else { continue }
        if let existing = hulls[name], existing < typeID { continue }
        hulls[name] = typeID
    }

    let modeIDs = types.elements
        .filter { $0.value.groupID.rawValue == UInt16(modeGroupID) }
        .keys
        .sorted()
    for modeID in modeIDs {
        let modeName = types.idToName[modeID] ?? "\(modeID.rawValue)"
        let words = modeName.split(separator: " ")
        guard words.count > 2, let hullID = hulls[words.dropLast(2).joined(separator: " ")] else {
            fatalError("Tactical modes: no hull for \"\(modeName)\" [\(modeID.rawValue)]")
        }
        types.addEffect("tacticalMode", toType: modeID)
        types.addAttribute("canFitShipType1", Float(hullID.rawValue), toType: modeID)
        // `fittingRequirements` was derived from the SDE attributes before the patch.
        types.update(modeID) { $0.fittingRequirements = .init(canFitShipGroup: [], canFitShipType: [hullID]) }
        types.addAttribute("tacticalModes", 1, toType: hullID)
    }
}

@MainActor
func patchAncillaryArmorRepairer() {
    dogmaEffects.append("naniteRepairPasteArmorDamageBonus", .init(id: .init(rawValue: extraEffectID + 1), category: .passive))
    dogmaEffects.append("fueledArmorRepairBonus", .init(id: .init(rawValue: extraEffectID + 3), category: .passive))
    dogmaAttributes.append("chargedArmorDamageMultiplierPostDiv", .init(id: .init(rawValue: extraAttributeID + 1), category: 5, minAttributeID: 0, maxAttributeID: 0, defaultValue: 0, unit: 0, options: [.isStackable, .highIsGood]))

    let attributeID = dogmaAttributes.nameToID["chargedArmorDamageMultiplier"]!
    let effectID = dogmaEffects.nameToID["fueledArmorRepair"]!

    for (typeID, type) in types.elements {
        if let value = type.attributes[attributeID] {
#warning("TODO: value == 1?")
            types.addAttribute("chargedArmorDamageMultiplierPostDiv", value, toType: typeID)
        }
        if type.effects.contains(where: {$0.id == effectID}) {
            types.addEffect("fueledArmorRepairBonus", toType: typeID)
        }
    }
    
    types.addEffect("naniteRepairPasteArmorDamageBonus", toType: "Nanite Repair Paste")
    types.addAttribute("chargedArmorDamageMultiplierPostDiv", 1, toType: "Nanite Repair Paste")
}

@MainActor
func patchFitting() {
    dogmaEffects.update("online") { effect in
        effect.category = .online
        effect.modifiers = [
            .item(.hull, "cpuLoad", .modAdd, "cpu"),
            .item(.hull, "powerLoad", .modAdd, "power")
        ]
    }
    
    dogmaEffects.update("onlineForStructures") {$0.category = .online}

    dogmaEffects.update("slotModifier") { effect in
        effect.modifiers = [
            .item(.hull, "hiSlots", .modAdd, "hiSlotModifier"),
            .item(.hull, "medSlots", .modAdd, "medSlotModifier"),
            .item(.hull, "lowSlots", .modAdd, "lowSlotModifier")
        ]
    }

    dogmaEffects.update("hardPointModifierEffect") { effect in
        effect.modifiers = [
            .item(.hull, "launcherSlotsLeft", .modAdd, "launcherHardPointModifier"),
            .item(.hull, "turretSlotsLeft", .modAdd, "turretHardPointModifier")
        ]
    }

}

@MainActor
func patchHardeners() {
    dogmaEffects.update("adaptiveArmorHardener") { effect in
        effect.modifiers = [
            .item(.hull, "armorEmDamageResonance", .postMul, "armorEmDamageResonance"),
            .item(.hull, "armorExplosiveDamageResonance", .postMul, "armorExplosiveDamageResonance"),
            .item(.hull, "armorKineticDamageResonance", .postMul, "armorKineticDamageResonance"),
            .item(.hull, "armorThermalDamageResonance", .postMul, "armorThermalDamageResonance")
        ]
    }
}

@MainActor
func patchRepairers() {
    dogmaEffects.update("fueledArmorRepairBonus") { effect in
        effect.modifiers = [
            .item(.self, "chargedArmorDamageMultiplier", .postDiv, "chargedArmorDamageMultiplierPostDiv"),
            .item(.self, "armorDamageAmount", .postMul, "chargedArmorDamageMultiplier")
        ]
    }
    
    dogmaEffects.update("naniteRepairPasteArmorDamageBonus") { effect in
        effect.modifiers = [ .item(.other, "chargedArmorDamageMultiplierPostDiv", .postAssignment, "chargedArmorDamageMultiplierPostDiv") ]
    }

    for effect in ["armorRepair", "fueledArmorRepair"] {
        dogmaEffects.update(effect) { effect in
            effect.modifiers = [ .item(.hull, "armorDamage", .subRate, "armorDamageAmount") ]
        }
    }

    // The mutadaptive repairer's spool multiplier lives in the read layer (`SpoolPolicy`), not in dogma.
    for effect in ["shipModuleRemoteArmorRepairer", "shipModuleAncillaryRemoteArmorRepairer",
                   "ShipModuleRemoteArmorMutadaptiveRepairer"] {
        dogmaEffects.update(effect) { effect in
            effect.modifiers = [ .item(.target, "armorDamage", .subRate, "armorDamageAmount") ]
        }
    }

    for effect in ["shieldBoosting", "fueledShieldBoosting"] {
        dogmaEffects.update(effect) { effect in
            effect.modifiers = [ .item(.hull, "shieldCharge", .addRate, "shieldBonus") ]
        }
    }

    for effect in ["shipModuleRemoteShieldBooster", "shipModuleAncillaryRemoteShieldBooster"] {
        dogmaEffects.update(effect) { effect in
            effect.modifiers = [ .item(.target, "shieldCharge", .addRate, "shieldBonus") ]
        }
    }

    dogmaEffects.update("structureRepair") { effect in
        effect.modifiers = [ .item(.hull, "damage", .subRate, "structureDamageAmount") ]
    }

    dogmaEffects.update("shipModuleRemoteHullRepairer") { effect in
        effect.modifiers = [ .item(.target, "damage", .subRate, "structureDamageAmount") ]
    }

}


@MainActor
func patchEnergyTransfers() {
    dogmaEffects.update("shipModuleRemoteCapacitorTransmitter") { effect in
        effect.modifiers = [ .item(.target, "charge", .addRate, "powerTransferAmount") ]
    }

    for effect in ["energyNeutralizerFalloff", "energyNosferatuFalloff"] {
        dogmaEffects.update(effect) { effect in
            effect.modifiers = [ .item(.target, "charge", .subRate, "powerTransferAmount") ]
        }
    }
}

@MainActor
func patchRemoteTrackingComputer() {
    dogmaEffects.update("shipModuleRemoteTrackingComputer") { effect in
        effect.modifiers = [
            .locationRequiredSkill(.target, "Gunnery", "trackingSpeed", .postPercent, "trackingSpeedBonus"),
            .locationRequiredSkill(.target, "Gunnery", "maxRange", .postPercent, "maxRangeBonus"),
            .locationRequiredSkill(.target, "Gunnery", "falloff", .postPercent, "falloffBonus")
        ]
    }
}

@MainActor
func patchConfessor() {
    dogmaEffects.update("modeVelocityPostDiv") { effect in
        effect.modifiers = [ .item(.hull, "maxVelocity", .postDiv, "modeVelocityPostDiv") ]
    }
    dogmaEffects.update("modeAgilityPostDiv") { effect in
        effect.modifiers = [ .item(.hull, "agility", .postDiv, "modeAgilityPostDiv") ]
    }
    dogmaEffects.update("modeArmorResonancePostDiv") { effect in
        effect.modifiers = [
            .item(.hull, "armorEmDamageResonance", .postDiv, "modeEmResistancePostDiv"),
            .item(.hull, "armorExplosiveDamageResonance", .postDiv, "modeExplosiveResistancePostDiv"),
            .item(.hull, "armorKineticDamageResonance", .postDiv, "modeKineticResistancePostDiv"),
            .item(.hull, "armorThermalDamageResonance", .postDiv, "modeThermicResistancePostDiv")
        ]
    }
    dogmaEffects.update("modeSigRadiusPostDiv") { effect in
        effect.modifiers = [ .item(.hull, "signatureRadius", .postDiv, "modeSignatureRadiusPostDiv") ]
    }
    dogmaEffects.update("shipModeScanStrengthPostDiv") { effect in
        effect.modifiers = [ .item(.hull, "scanRadarStrength", .postDiv, "modeRadarStrengthPostDiv") ]
    }
    dogmaEffects.update("shipModeSETOptimalRangePostDiv") { effect in
        effect.modifiers = [ .locationRequiredSkill(.hull, "Small Energy Turret", "maxRange", .postDiv, "modeMaxRangePostDiv") ]
    }
    dogmaEffects.update("shipModeMaxTargetRangePostDiv") { effect in
        effect.modifiers = [ .item(.hull, "maxTargetRange", .postDiv, "modeMaxTargetRangePostDiv") ]
    }
}

@MainActor
func patchSvipul() {
    dogmaEffects.update("modeShieldResonancePostDiv") { effect in
        effect.modifiers = [
            .item(.hull, "shieldEmDamageResonance", .postDiv, "modeEmResistancePostDiv"),
            .item(.hull, "shieldExplosiveDamageResonance", .postDiv, "modeExplosiveResistancePostDiv"),
            .item(.hull, "shieldKineticDamageResonance", .postDiv, "modeKineticResistancePostDiv"),
            .item(.hull, "shieldThermalDamageResonance", .postDiv, "modeThermicResistancePostDiv")
        ]
    }
    dogmaEffects.update("shipModeSPTTrackingPostDiv") { effect in
        effect.modifiers = [ .locationRequiredSkill(.hull, "Small Projectile Turret", "trackingSpeed", .postDiv, "modeTrackingPostDiv") ]
    }
    dogmaEffects.update("modeMWDSigRadiusPostDiv") { effect in
        effect.modifiers = [ .locationRequiredSkill(.hull, "High Speed Maneuvering", "signatureRadiusBonus", .postDiv, "modeMWDSigPenaltyPostDiv") ]
    }
}

@MainActor
func patchJackdaw() {
    dogmaEffects.update("shipModeMissileVelocityPostDiv") { effect in
        effect.modifiers = [ .ownerRequiredSkill(.pilot, "Missile Launcher Operation", "maxVelocity", .postDiv, "modeMaxRangePostDiv") ]
    }
}

@MainActor
func patchHecate() {
    dogmaEffects.update("modeHullResonancePostDiv") { effect in
        effect.modifiers = [
            .item(.hull, "emDamageResonance", .postDiv, "modeEmResistancePostDiv"),
            .item(.hull, "explosiveDamageResonance", .postDiv, "modeExplosiveResistancePostDiv"),
            .item(.hull, "kineticDamageResonance", .postDiv, "modeKineticResistancePostDiv"),
            .item(.hull, "thermalDamageResonance", .postDiv, "modeThermicResistancePostDiv")
        ]
    }
    dogmaEffects.update("modeArmorRepDurationPostDiv") { effect in
        effect.modifiers = [ .locationRequiredSkill(.hull, "Repair Systems", "duration", .postDiv, "modeArmorRepDurationPostDiv") ]
    }
    dogmaEffects.update("modeMWDBoostPostDiv") { effect in
        effect.modifiers = [ .locationRequiredSkill(.hull, "High Speed Maneuvering", "speedFactor", .postDiv, "modeMWDVelocityPostDiv") ]
    }
    dogmaEffects.update("modeMWDCapPostDiv") { effect in
        effect.modifiers = [ .locationRequiredSkill(.hull, "High Speed Maneuvering", "capacitorNeed", .postDiv, "modeMWDCapPostDiv") ]
    }
    dogmaEffects.update("shipModeSHTOptimalRangePostDiv") { effect in
        effect.modifiers = [ .locationRequiredSkill(.hull, "Small Hybrid Turret", "maxRange", .postDiv, "modeMaxRangePostDiv") ]
    }
}

@MainActor
func patchSpeedBoost() {
    dogmaAttributes.append("speedBoostFactorCalc", .init(id: 576, category: 9, minAttributeID: 0, maxAttributeID: 0, defaultValue: 0.01, unit: 0, options: [.isStackable, .highIsGood]))
    dogmaAttributes.append("speedBoostFactorCalc2", .init(id: 578, category: 9, minAttributeID: 0, maxAttributeID: 0, defaultValue: 1.0, unit: 0, options: [.isStackable, .highIsGood]))
    
    dogmaEffects.append("speedBoostFactorCalculator", .init(id: 710, category: .passive))
    dogmaEffects.append("speedBoostFactorCalculator2", .init(id: 712, category: .passive))
    dogmaEffects.append("massFactor", .init(id: 1171, category: .passive))

    types.addEffect("speedBoostFactorCalculator", toGroup: "Propulsion Module")
    types.addEffect("speedBoostFactorCalculator2", toGroup: "Propulsion Module")
    
    dogmaEffects.update("speedBoostFactorCalculator") { effect in
        effect.modifiers = [
            .item(.self, "speedBoostFactorCalc", .postMul, "speedFactor"),
            .item(.self, "speedBoostFactorCalc", .postMul, "speedBoostFactor")
        ]
    }
    dogmaEffects.update("speedBoostFactorCalculator2") { effect in
        effect.modifiers = [ .item(.self, "speedBoostFactorCalc2", .modAdd, "speedBoostFactorCalc") ]
    }
    dogmaEffects.update("moduleBonusAfterburner") { effect in
        effect.modifiers = [
            .item(.hull, "maxVelocity", .postMul, "speedBoostFactorCalc2"),
            .item(.hull, "mass", .modAdd, "massAddition")
        ]
    }
    dogmaEffects.update("moduleBonusMicrowarpdrive") { effect in
        effect.modifiers = [
            .item(.hull, "maxVelocity", .postMul, "speedBoostFactorCalc2"),
            .item(.hull, "mass", .modAdd, "massAddition"),
            .item(.hull, "signatureRadius", .postPercent, "signatureRadiusBonus")
        ]
    }
    dogmaEffects.update("massFactor") { effect in
        effect.modifiers = [ .locationGroup(.self, "Propulsion Module", "speedBoostFactorCalc", .postDiv, "mass") ]
    }
    
    types.addEffect("massFactor", toCategory: "Ship")
}

@MainActor
func patchMissing() {
    dogmaEffects.update("droneDmgBonus") { effect in
        effect.modifiers = [ .locationRequiredDomainSkill(.pilot, "damageMultiplier", .postPercent, "damageMultiplierBonus", .self) ]
    }
    dogmaEffects.update("selfRof") { effect in
        effect.modifiers = [ .locationRequiredDomainSkill(.hull, "speed", .postPercent, "rofBonus", .self) ]
    }
    dogmaEffects.update("launcherFitted") { effect in
        effect.modifiers = [ .item(.hull, "launcherSlotsLeft", .modSub, "slots") ]
    }
    dogmaEffects.update("turretFitted") { effect in
        effect.modifiers = [ .item(.hull, "turretSlotsLeft", .modSub, "slots") ]
    }
    dogmaEffects.update("missileEMDmgBonus") { effect in
        effect.modifiers = [ .locationRequiredDomainSkill(.pilot, "emDamage", .postPercent, "damageMultiplierBonus", .self) ]
    }
    dogmaEffects.update("missileExplosiveDmgBonus") { effect in
        effect.modifiers = [ .locationRequiredDomainSkill(.pilot, "explosiveDamage", .postPercent, "damageMultiplierBonus", .self) ]
    }
    dogmaEffects.update("missileThermalDmgBonus") { effect in
        effect.modifiers = [ .locationRequiredDomainSkill(.pilot, "thermalDamage", .postPercent, "damageMultiplierBonus", .self) ]
    }
    dogmaEffects.update("missileKineticDmgBonus2") { effect in
        effect.modifiers = [ .locationRequiredDomainSkill(.pilot, "kineticDamage", .postPercent, "damageMultiplierBonus", .self) ]
    }
    dogmaEffects.update("cloakingTargetingDelayBonusPostPercentCloakingTargetingDelayBonusForShipModulesRequiringCloaking") { effect in
        effect.modifiers = [ .locationRequiredDomainSkill(.hull, "cloakingTargetingDelay", .postPercent, "cloakingTargetingDelayBonus", .self) ]
    }
}

@MainActor
func patchSubsystems() {
    let attributeID = dogmaAttributes.nameToID["maxSubSystems"]!
    for (typeID, type) in types.elements {
        if type.attributes[attributeID] != nil {
            types.update(typeID) { type in
                type.attributes[attributeID] = 4
            }
        }
    }
}

/// Celestial groups let through the importer whitelist (see main.swift). `Effect Beacon` carries
/// ordinary modifiers; the others hand out warfare buffs and get the `environmentBoost` marker below.
let environmentGroupNames: Set<String> = [
    "Effect Beacon",
    "Abyssal Hazards",
    "Non-Interactable Object",
    "MassiveEnvironments",
    "Triglavian Support Pylons",
]

/// Marker effects that act as warfare-buff sources. They carry no modifiers: on seeing one, the engine reads
/// `warfareBuff{1...4}ID` (own or charge) and takes modifiers from `warfareBuffs`, magnitude from `warfareBuff{N}Value`.
/// `.activation` effects apply only while the module is active; `.environment` effects are always on.
/// Idempotent.
@MainActor
func patchWarfareBuffSources() {
    if dogmaEffects["gangBoost"] == nil {
        dogmaEffects.append("gangBoost", .init(id: .init(rawValue: extraEffectID + 4), category: .activation))
        types.addEffect("gangBoost", toGroup: "Command Burst")
        types.addEffect("gangBoost", toGroup: "Titan Phenomena Generator")
    }
    if dogmaEffects["environmentBoost"] == nil {
        dogmaEffects.append("environmentBoost", .init(id: .init(rawValue: extraEffectID + 5), category: .environment))
        // `Effect Beacon` is excluded: beacons carry their own modifiers and need no marker.
        for group in environmentGroupNames.subtracting(["Effect Beacon"]).sorted() {
            types.addEffect("environmentBoost", toGroupIfPresent: group)
        }
    }
}

@MainActor
func patch() {
    dogmaAttributes.append("none", .init(id: 0, category: 0, minAttributeID: 0, maxAttributeID: 0, defaultValue: 0, unit: 0, options: []))
    patchMissilesDamage()
    patchTacticalModes()
    patchAncillaryArmorRepairer()
    patchFitting()
    patchHardeners()
    patchRepairers()
    patchEnergyTransfers()
    patchRemoteTrackingComputer()
    patchSpeedBoost()
    patchMissing()
    patchSubsystems()
    patchWarfareBuffSources()
}
