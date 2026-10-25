//
//  AncillariesTests.swift
//  DogmaKit
//
//  Ancillary modules (repairers/boosters that use a charge):
//  - adding a large ancillary armor repairer raises armorRepair;
//  - loading a charge (nanite repair paste) raises repair further;
//  - capacitor drain: no booster < booster with charge < booster without charge.
//

import Testing
@testable import DogmaKit

@Suite("Ancillaries", .setupDebugNames)
struct AncillariesTests {

    @Test("Adding a largeAncillaryArmorRepairer raises armorRepair")
    func ancillaryArmorRepairerIncreasesTank() async throws {
        let engine = DogmaEngine()

        try await engine.edit { fit in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: .dominix)
        }

        let tank0 = await engine.evaluate { stats in
            let hull = stats[PilotID(1).hull]
            return hull.tank().armorRepair
        }

        try await engine.edit { fit in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: .dominix)
            _ = try hull.modules.add(.largeAncillaryArmorRepairer)
        }

        let tank1 = await engine.evaluate { stats in
            let hull = stats[PilotID(2).hull]
            return hull.tank().armorRepair
        }

        #expect(tank1 > tank0, "tank1 = \(tank1), tank0 = \(tank0)")

        try await engine.edit { fit in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: .dominix)
            let repairer = try hull.modules.add(.largeAncillaryArmorRepairer)
            _ = try repairer.setCharge(.naniteRepairPaste)
        }

        // The reload policy is a read setting, so the modes are compared with two
        // evaluate calls; neither triggers a recalculation.
        let tank2 = await engine.evaluate(reload: .factored) { stats in
            stats[PilotID(3).hull].tank().armorRepair
        }

        let tank3 = await engine.evaluate(reload: .ignored) { stats in
            stats[PilotID(3).hull].tank().armorRepair
        }

        #expect(tank2 > tank1, "tank2 = \(tank2), tank1 = \(tank1)")
        #expect(tank3 > tank2, "peak tank is above sustained: tank3 = \(tank3), tank2 = \(tank2)")
    }

    @Test("A booster with a charge drains less capacitor than one without")
    func shieldBoosterCapacitorDrain() async throws {
        let engine = DogmaEngine()

        try await engine.edit { fit in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: .dominix)
        }
        
        let capUsed0 = await engine.evaluate { stats in
            let hull = stats[PilotID(1).hull]
            return hull.capacitor().averageDrain
        }

        try await engine.edit { fit in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: .dominix)
            _ = try hull.modules.add(.largeAncillaryShieldBooster)
        }

        let capUsed1 = await engine.evaluate { stats in
            let hull = stats[PilotID(2).hull]
            return hull.capacitor().averageDrain
        }

        #expect(capUsed1 > capUsed0, "capUsed1 = \(capUsed1), capUsed0 = \(capUsed0)")

        try await engine.edit { fit in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: .dominix)
            let booster = try hull.modules.add(.largeAncillaryShieldBooster)
            _ = try booster.setCharge(.capBooster200)
        }

        let capUsed2 = await engine.evaluate { stats in
            let hull = stats[PilotID(3).hull]
            return hull.capacitor().averageDrain
        }

        #expect(capUsed0 < capUsed1 && capUsed1 > capUsed2, "capUsed0 = \(capUsed0), capUsed1 = \(capUsed1), capUsed2 = \(capUsed2)")
    }

    @Test("ASB tank with cap boosters accounts for clip reload")
    func ancillaryShieldBoosterTankFactorsReload() async throws {
        let engine = DogmaEngine()

        try await engine.edit { fit in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: .dominix)
            let booster = try hull.modules.add(.largeAncillaryShieldBooster)
            _ = try booster.setCharge(.capBooster200)
        }

        let (tankRepair, rawRate, cycleRate) = await engine.evaluate { stats in
            let hull = stats[PilotID(1).hull]
            let moduleID = hull.modules.ids(in: .med).first { _ in true }!
            let module = hull.modules[moduleID]
            let bonus = module.attributes[.shieldBonus] ?? 0
            return (hull.sustainableTank().shieldRepair,
                    bonus / module.rawCycleTime,
                    bonus / module.cycleTime())
        }

        // The rate uses the cycle WITH reload, not the raw duration.
        #expect(tankRepair > 0)
        #expect(abs(tankRepair - cycleRate) < 1e-9, "tank = \(tankRepair), expected \(cycleRate)")
        #expect(tankRepair < rawRate, "clip reload must lower the rate: \(tankRepair) vs \(rawRate)")
    }

    /// Nanite repair paste multiplies the per-cycle armor repair by `chargedArmorDamageMultiplier` (3).
    /// Covers every kind of ancillary armor repairer: a plain one, an abyssal one (its final type
    /// carries no `chargedArmorDamageMultiplier` of its own — it comes from the base type) and a
    /// remote one (a different repair effect).
    @Test("Nanite repair paste triples armorDamageAmount", arguments: [
        (TypeID.largeAncillaryArmorRepairer, TypeID?.none),
        (.largeAncillaryArmorRepairer, .unstableLargeAncillaryArmorRepairerMutaplasmid),
        (.largeAncillaryRemoteArmorRepairer, nil)
    ])
    func naniteRepairPasteTriplesRepair(typeID: TypeID, mutaplasmid: TypeID?) async throws {
        let engine = DogmaEngine()
        let moduleIDs = try await engine.edit { fit -> [ModuleID] in
            var moduleIDs: [ModuleID] = []
            for isLoaded in [false, true] {
                let pilot = try fit.pilots.add(skillLevel: 5)
                let hull = pilot.hull
                try hull.set(typeID: .dominix)
                if let mutaplasmid {
                    let module = try hull.modules.add(typeID, mutaplasmid: mutaplasmid)
                    if isLoaded { try module.setCharge(.naniteRepairPaste) }
                    moduleIDs.append(module.id)
                } else {
                    let module = try hull.modules.add(typeID)
                    if isLoaded { try module.setCharge(.naniteRepairPaste) }
                    moduleIDs.append(module.id)
                }
            }
            return moduleIDs
        }
        let amounts = await engine.evaluate { stats -> [Double] in
            var amounts: [Double] = []
            for moduleID in moduleIDs {
                amounts.append(stats[moduleID].attributes[.armorDamageAmount] ?? 0)
            }
            return amounts
        }
        #expect(amounts[0] > 0)
        #expect(abs(amounts[1] / amounts[0] - 3) < 1e-9, "unloaded = \(amounts[0]), loaded = \(amounts[1])")
    }
}
