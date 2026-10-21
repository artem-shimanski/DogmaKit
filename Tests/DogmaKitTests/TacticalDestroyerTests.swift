//
//  TacticalDestroyerTests.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 30.07.2026.
//

import Testing
@testable import DogmaKit

@Suite("Tactical destroyers", .setupDebugNames)
struct TacticalDestroyerTests {
    
    @Test("Hecate tactical modes")
    func hecateTacticalModes() async throws {
        let engine = DogmaEngine()
        let hullID = PilotID(1).hull
        
        var tacticalModeID = try await engine.edit { fit -> ModuleID in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: .hecate)
            
            try hull.modules.add(._5MNMicrowarpdriveII)
            try hull.modules.add(.smallArmorRepairerII)
            try hull.modules.add(.smallShieldBoosterII)
            let mode = try hull.modules.add(.hecateDefenseMode)
            
            return mode.id
        }
        
        let (cap0, v0, tank0, res0) = await engine.evaluate { stats in
            let hull = stats[hullID]
            return (hull.capacitor(), hull.navigation.maxVelocity, hull.tank(), hull.resistances)
        }
        
        tacticalModeID = try await engine.edit { [tacticalModeID] fit -> ModuleID in
            let hull = fit[hullID]
            fit[tacticalModeID].remove()
            return try hull.modules.add(.hecatePropulsionMode).id
        }
        
        let (cap1, v1, tank1, res1) = await engine.evaluate { stats in
            let hull = stats[hullID]
            return (hull.capacitor(), hull.navigation.maxVelocity, hull.tank(), hull.resistances)
        }
        
        #expect(cap1.delta > cap0.delta, "hecatePropulsionMode reduces the MWD capacitor use")
        #expect(v1 > v0, "hecatePropulsionMode increases the MWD speed bonus")
        #expect(tank0.armorRepair > tank1.armorRepair, "hecateDefenseMode increases armor repairer effectiveness")
        #expect(abs(tank0.shieldRepair - tank1.shieldRepair) < 1e-6, "hecateDefenseMode does not affect the shield booster")
        #expect(res0.armor.sum() > res1.armor.sum(), "hecateDefenseMode increases armor resistances")
        #expect(res0.hull.sum() > res1.hull.sum(), "hecateDefenseMode increases hull resistances")
        #expect(abs(res0.shield.sum() - res1.shield.sum()) < 1e-6, "hecateDefenseMode does not affect shield resistances")
    }

    // MARK: - Anhinga and Skua

    private static let hullID = PilotID(1).hull

    /// Values a mode may change: the hull's, the first high-slot module's and its charge's.
    private struct Probe {
        var maxTargetRange = 0.0
        var agility = 0.0
        var shieldRechargeRate = 0.0
        var shieldResonance = 0.0
        var launcherSpeed = 0.0
        var flightTime = 0.0
        var missileVelocity = 0.0
        var missileDamage = 0.0
    }

    private func probe(hull hullType: TypeID,
                       launcher: TypeID,
                       charge: TypeID,
                       mode: TypeID?) async throws -> Probe {
        let engine = DogmaEngine()
        try await engine.edit { fit in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: hullType)
            let module = try hull.modules.add(launcher)
            try module.setCharge(charge)
            if let mode {
                try hull.modules.add(mode)
            }
        }
        return await engine.evaluate { stats in
            let hull = stats[Self.hullID]
            var result = Probe()
            result.maxTargetRange = hull.attributes[.maxTargetRange] ?? 0
            result.agility = hull.attributes[.agility] ?? 0
            result.shieldRechargeRate = hull.attributes[.shieldRechargeRate] ?? 0
            result.shieldResonance = hull.attributes[.shieldEmDamageResonance] ?? 0
            hull.modules.forEach(in: .hi) { module in
                result.launcherSpeed = module.attributes[.speed] ?? 0
                if let charge = module.charge {
                    result.flightTime = charge.attributes[.explosionDelay] ?? 0
                    result.missileVelocity = charge.attributes[.maxVelocity] ?? 0
                    result.missileDamage = charge.attributes[.emDamage] ?? 0
                }
            }
            return result
        }
    }

    private func anhinga(_ mode: TypeID?) async throws -> Probe {
        try await probe(hull: .anhinga, launcher: .torpedoLauncherII, charge: .mjolnirTorpedo, mode: mode)
    }

    private func skua(_ mode: TypeID?) async throws -> Probe {
        try await probe(hull: .skua, launcher: .lightMissileLauncherII, charge: .mjolnirLightMissile, mode: mode)
    }

    private func ratio(_ a: Double, _ b: Double) -> Double { b == 0 ? .nan : a / b }

    @Test("Anhinga and Skua have one mode slot")
    func modeSlot() async throws {
        for hullType in [TypeID.anhinga, .skua] {
            let engine = DogmaEngine()
            try await engine.edit { fit in
                let pilot = try fit.pilots.add(skillLevel: 5)
                let hull = pilot.hull
                try hull.set(typeID: hullType)
            }
            let total = await engine.evaluate { stats in
                let hull = stats[Self.hullID]
                return hull.capacity(of: .mode).total
            }
            #expect(total == 1, "\(hullType)")
        }
    }

    // The Anhinga multipliers look extreme (flight time x11, lock range x5), but they are the
    // values the game uses.
    @Test("Anhinga Primary Mode: lock range and torpedo flight time")
    func anhingaPrimary() async throws {
        let base = try await anhinga(nil)
        let mode = try await anhinga(.anhingaPrimaryMode)
        // Lock range is capped at 300 km by `maximumRangeCap`.
        #expect(abs(mode.maxTargetRange - min(base.maxTargetRange / 0.2, 300_000)) < 1e-3)
        #expect(abs(ratio(mode.flightTime, base.flightTime) - 1 / 0.0909) < 1e-3)
        #expect(abs(ratio(mode.missileVelocity, base.missileVelocity) - 1 / 1.5) < 1e-3)
        #expect(abs(ratio(mode.launcherSpeed, base.launcherSpeed) - 1 / 1.333) < 1e-3)
    }

    @Test("Anhinga Secondary Mode: half the flight time, twice the rate of fire")
    func anhingaSecondary() async throws {
        let base = try await anhinga(nil)
        let mode = try await anhinga(.anhingaSecondaryMode)
        #expect(abs(ratio(mode.flightTime, base.flightTime) - 0.5) < 1e-3)
        #expect(abs(ratio(mode.launcherSpeed, base.launcherSpeed) - 0.5) < 1e-3)
        #expect(mode.maxTargetRange == base.maxTargetRange)
    }

    @Test("Anhinga Tertiary Mode: rate of fire and agility")
    func anhingaTertiary() async throws {
        let base = try await anhinga(nil)
        let mode = try await anhinga(.anhingaTertiaryMode)
        #expect(abs(ratio(mode.launcherSpeed, base.launcherSpeed) - 1 / 1.333) < 1e-3)
        #expect(abs(ratio(mode.agility, base.agility) - 1 / 1.333) < 1e-3)
        #expect(mode.flightTime == base.flightTime)
    }

    @Test("Skua Defense Mode: shield resistances and recharge")
    func skuaDefense() async throws {
        let base = try await skua(nil)
        let mode = try await skua(.skuaDefenseMode)
        #expect(abs(ratio(mode.shieldResonance, base.shieldResonance) - 1 / 1.5) < 1e-3)
        #expect(abs(ratio(mode.shieldRechargeRate, base.shieldRechargeRate) - 1 / 1.5) < 1e-3)
    }

    @Test("Skua Sharpshooter Mode: light missile damage and velocity")
    func skuaSharpshooter() async throws {
        let base = try await skua(nil)
        let mode = try await skua(.skuaSharpshooterMode)
        #expect(abs(ratio(mode.missileDamage, base.missileDamage) - 1 / 0.75) < 1e-3)
        #expect(abs(ratio(mode.missileVelocity, base.missileVelocity) - 1 / 0.6) < 1e-3)
        #expect(abs(ratio(mode.maxTargetRange, base.maxTargetRange) - 1 / 0.5) < 1e-3)
    }

    @Test("Every tactical mode fits its own hull and no other")
    func everyModeHasAHull() throws {
        let catalog = try TypeCatalog()
        let modes = catalog.typeIDs(inGroup: .shipModifiers)
        #expect(modes.count >= 18)
        for mode in modes {
            #expect(catalog.slot(of: mode) == .mode, "\(mode)")
            let hulls = [TypeID.confessor, .svipul, .jackdaw, .hecate, .anhinga, .skua].filter {
                catalog.canFit(mode, to: $0)
            }
            #expect(hulls.count == 1, "\(mode) fits \(hulls)")
            guard let hull = hulls.first else { continue }
            #expect(catalog.attribute(.tacticalModes, of: hull) == 1, "\(hull)")
            #expect(!catalog.canFit(mode, to: .rifter), "\(mode)")
        }
    }

    @Test("A mode on a hull without modes is rejected")
    func modeOnOtherHull() async throws {
        let engine = DogmaEngine()
        await #expect(throws: DogmaError.self) {
            try await engine.edit { fit in
                let pilot = try fit.pilots.add(skillLevel: 5)
                let hull = pilot.hull
                try hull.set(typeID: .rifter)
                try hull.modules.add(.anhingaPrimaryMode)
            }
        }
    }

    @Test("A module with no slot throws instead of trapping")
    func slotlessModuleThrows() async throws {
        let engine = DogmaEngine()
        let error = await engine.edit { fit -> DogmaError? in
            do {
                let pilot = try fit.pilots.add(skillLevel: 5)
                let hull = pilot.hull
                try hull.set(typeID: .apocalypse)
                try hull.modules.add(.luxKontos)
                return nil
            } catch {
                return error as? DogmaError
            }
        }
        guard case .noSlot(let typeID) = error else {
            Issue.record("expected noSlot, got \(String(describing: error))")
            return
        }
        #expect(typeID == .luxKontos)
        #expect(try TypeCatalog().slot(of: .luxKontos) == nil)
    }

    @Test("A document with an unfittable module loads without it")
    func documentSkipsUnfittableModules() async throws {
        var document = FitDocument()
        document.pilots = [
            .init(skills: .init(default: 5),
                  ship: .init(type: .rifter, modules: [.init(type: .anhingaPrimaryMode), .init(type: .luxKontos)])),
        ]
        let engine = DogmaEngine()
        let warnings = try await engine.load(document)
        #expect(warnings.count == 2)
        for warning in warnings {
            guard case .typeRejected = warning else {
                Issue.record("expected typeRejected, got \(warning)")
                continue
            }
        }
        let count = await engine.evaluate { stats in
            let hull = stats[Self.hullID]
            return hull.modules.count
        }
        #expect(count == 0)
    }
}
