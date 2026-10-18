//
//  RemoteRepairerTests.swift
//  DogmaKit
//
//  Projected repairers: remote armor repairer, shield booster and hull repairer targeting
//  another hull must increase the target's tank.
//

import Testing
@testable import DogmaKit

@Suite("Remote repairers", .setupDebugNames)
struct RemoteRepairerTests {

    private static let firstHull = PilotID(1).hull
    private static let secondHull = PilotID(2).hull

    @Test("Target armor, shield and hull repair are above zero once remote repairers are applied")
    func armorShieldHullRepairIncrease() async throws {
        let engine = DogmaEngine()
        try await engine.edit { fit in
            let pilotA = try fit.pilots.add(skillLevel: 5)
            let pilotB = try fit.pilots.add(skillLevel: 5)

            let hullA = pilotA.hull
            let hullB = pilotB.hull
            try hullA.set(typeID: .dominix)
            try hullB.set(typeID: .dominix)

            let repairers: [TypeID] = [.largeRemoteArmorRepairerI, .largeRemoteShieldBoosterI, .largeRemoteHullRepairerI]
            for typeID in repairers {
                let module = try hullA.modules.add(typeID)
                module.target = pilotB.id.hull  // target hull B
            }
        }

        let tank1 = await engine.evaluate { stats in
            stats[Self.secondHull].tank()
        }

        #expect(tank1.armorRepair > 0, "largeRemoteArmorRepairerI gives the target positive armor repair")
        #expect(tank1.shieldRepair > 0, "largeRemoteShieldBoosterI gives the target positive shield repair")
        #expect(tank1.hullRepair > 0, "largeRemoteHullRepairerI gives the target positive hull repair")
    }

    @Test("The target's tank is larger with remote repairers than without")
    func tankWithRemoteIsGreater() async throws {
        let engineBase = DogmaEngine()
        try await engineBase.edit { fit in
            let pilotA = try fit.pilots.add(skillLevel: 5)
            let pilotB = try fit.pilots.add(skillLevel: 5)

            let hullA = pilotA.hull
            let hullB = pilotB.hull
            try hullA.set(typeID: .dominix)
            try hullB.set(typeID: .dominix)
        }

        let engineRepairers = DogmaEngine()
        try await engineRepairers.edit { fit in
            let pilotA = try fit.pilots.add(skillLevel: 5)
            let pilotB = try fit.pilots.add(skillLevel: 5)

            let hullA = pilotA.hull
            let hullB = pilotB.hull
            try hullA.set(typeID: .dominix)
            try hullB.set(typeID: .dominix)

            let repairers: [TypeID] = [.largeRemoteArmorRepairerI, .largeRemoteShieldBoosterI, .largeRemoteHullRepairerI]
            for typeID in repairers {
                let module = try hullA.modules.add(typeID)
                module.target = pilotB.id.hull  // target hull B
            }
        }

        func tank(_ e: DogmaEngine) async -> Tank {
            await e.evaluate { stats in
                stats[Self.secondHull].tank()
            }
        }

        let tank0 = await tank(engineBase)
        let tank1 = await tank(engineRepairers)

        #expect(tank1.armorRepair > tank0.armorRepair, "armor repair: \(tank1.armorRepair) vs \(tank0.armorRepair)")
        #expect(tank1.shieldRepair > tank0.shieldRepair, "shield repair: \(tank1.shieldRepair) vs \(tank0.shieldRepair)")
        #expect(tank1.hullRepair > tank0.hullRepair, "hull repair: \(tank1.hullRepair) vs \(tank0.hullRepair)")
    }
}
