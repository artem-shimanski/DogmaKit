//
//  SpoolTests.swift
//  DogmaKit
//
//  Spool-up of modules with growing output: entropic disintegrators
//  (damageMultiplierBonus{Max,PerCycle}) and mutadaptive remote repairers
//  (repairMultiplierBonus{Max,PerCycle}).
//

import Testing
@testable import DogmaKit

@Suite("Spool-up", .setupDebugNames)
struct SpoolTests {

    private static let firstHull = PilotID(1).hull

    private static func total(_ damage: DamageVector) -> Double {
        damage.em + damage.thermal + damage.kinetic + damage.explosive
    }

    /// Vedmak + Heavy Entropic Disintegrator II with Occult M.
    private static func disintegratorEngine() async throws -> DogmaEngine {
        let engine = DogmaEngine()
        try await engine.edit { fit in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: .vedmak)
            let gun = try hull.modules.add(.heavyEntropicDisintegratorII)
            gun.state = .active
            try gun.setCharge(.occultM)
        }
        return engine
    }

    /// Rodiva + Heavy Mutadaptive Remote Armor Repairer II.
    private static func mutadaptiveEngine() async throws -> DogmaEngine {
        let engine = DogmaEngine()
        try await engine.edit { fit in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: .rodiva)
            let repairer = try hull.modules.add(.heavyMutadaptiveRemoteArmorRepairerII)
            repairer.state = .active
        }
        return engine
    }

    // MARK: - Damage

    @Test("A cold disintegrator hits at base, a spooled one at the cap")
    func disintegratorSpoolBounds() async throws {
        let engine = try await Self.disintegratorEngine()

        let (cold, maxBonus, perCycle, cycles) = await engine.evaluate(spool: .none) { stats in
            let hull = stats[Self.firstHull]
            let moduleID = hull.modules.ids(in: .hi).first { _ in true }!
            let module = hull.modules[moduleID]
            return (Self.total(module.volleyDamage),
                    module.attributes[.damageMultiplierBonusMax] ?? 0,
                    module.attributes[.damageMultiplierBonusPerCycle] ?? 0,
                    module.spool(.damage)?.cycles ?? -1)
        }

        #expect(cold > 0)
        #expect(maxBonus > 0 && perCycle > 0, "a disintegrator must have the spool attribute pair")
        #expect(cycles == 0, "no cycles with .none: \(cycles)")

        // The spool policy is a read setting: no recalculation, a second `evaluate` is enough.
        let (full, spool) = await engine.evaluate(spool: .full) { stats in
            let hull = stats[Self.firstHull]
            let moduleID = hull.modules.ids(in: .hi).first { _ in true }!
            let module = hull.modules[moduleID]
            return (Self.total(module.volleyDamage), module.spool(.damage)!)
        }

        #expect(spool.isFull)
        #expect(abs(spool.bonus - maxBonus) < 1e-9, "full spool equals the cap: \(spool.bonus) vs \(maxBonus)")
        #expect(abs(full - cold * (1 + maxBonus)) < 1e-6,
                "spooled volley = base x (1 + max): \(full) vs \(cold * (1 + maxBonus))")

        // Cycles to the cap round up (2.125 / 0.07 -> 31).
        let expectedCycles = Int((maxBonus / perCycle).rounded(.up))
        #expect(spool.cycles == expectedCycles, "\(spool.cycles) vs \(expectedCycles)")
    }

    @Test("Damage grows monotonically with the spool scale and stops at the cap")
    func disintegratorScaleIsMonotonic() async throws {
        let engine = try await Self.disintegratorEngine()

        var values: [Double] = []
        for scale in [0.0, 0.25, 0.5, 0.75, 1.0, 2.0] {
            let value = await engine.evaluate(spool: .scale(scale)) { stats in
                let hull = stats[Self.firstHull]
                let moduleID = hull.modules.ids(in: .hi).first { _ in true }!
                return Self.total(hull.modules[moduleID].volleyDamage)
            }
            values.append(value)
        }

        for (index, pair) in zip(values, values.dropFirst()).enumerated() where index < 4 {
            #expect(pair.1 > pair.0, "step \(index) does not increase: \(values)")
        }
        #expect(abs(values[5] - values[4]) < 1e-9, "scale > 1 is clamped: \(values)")
    }

    @Test("Time-based spool counts whole cycles only")
    func disintegratorSpoolByTime() async throws {
        let engine = try await Self.disintegratorEngine()

        let (cycleTime, perCycle, maxBonus) = await engine.evaluate { stats in
            let hull = stats[Self.firstHull]
            let moduleID = hull.modules.ids(in: .hi).first { _ in true }!
            let module = hull.modules[moduleID]
            return (module.rawCycleTime,
                    module.attributes[.damageMultiplierBonusPerCycle] ?? 0,
                    module.attributes[.damageMultiplierBonusMax] ?? 0)
        }
        #expect(cycleTime > 0)

        // Just under three cycles counts as two.
        let almostThree = cycleTime * 3 - cycleTime / 10
        let spool = await engine.evaluate(spool: .time(almostThree)) { stats in
            let hull = stats[Self.firstHull]
            let moduleID = hull.modules.ids(in: .hi).first { _ in true }!
            return hull.modules[moduleID].spool(.damage)!
        }

        #expect(spool.cycles == 2, "expected 2 whole cycles: \(spool.cycles)")
        #expect(abs(spool.bonus - 2 * perCycle) < 1e-9)
        #expect(abs(spool.time - 2 * cycleTime) < 1e-9)

        // Very long runs hit the cap.
        let long = await engine.evaluate(spool: .time(cycleTime * 10_000)) { stats in
            let hull = stats[Self.firstHull]
            let moduleID = hull.modules.ids(in: .hi).first { _ in true }!
            return hull.modules[moduleID].spool(.damage)!
        }
        #expect(abs(long.bonus - maxBonus) < 1e-9, "\(long.bonus) vs \(maxBonus)")
    }

    @Test("A regular turret has no spool and ignores the policy")
    func regularTurretHasNoSpool() async throws {
        let engine = DogmaEngine()
        try await engine.edit { fit in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: .dominix)
            let turret = try hull.modules.add(._425mmAutoCannonII)
            turret.state = .active
            try turret.setCharge(.fusionM)
        }

        func volley(_ policy: SpoolPolicy) async -> (Double, Bool) {
            await engine.evaluate(spool: policy) { stats in
                let hull = stats[Self.firstHull]
                let moduleID = hull.modules.ids(in: .hi).first { _ in true }!
                let module = hull.modules[moduleID]
                return (Self.total(module.volleyDamage), module.spool == nil)
            }
        }

        let (cold, coldNoSpool) = await volley(.none)
        let (hot, hotNoSpool) = await volley(.full)

        #expect(coldNoSpool && hotNoSpool, "an autocannon has no spool attribute pair")
        #expect(cold > 0)
        #expect(abs(cold - hot) < 1e-9, "volley must not depend on the policy: \(cold) vs \(hot)")
    }

    // MARK: - Repair

    @Test("A mutadaptive repairer ramps up to repairMultiplierBonusMax")
    func mutadaptiveRepairSpool() async throws {
        let engine = try await Self.mutadaptiveEngine()

        let (cold, maxBonus) = await engine.evaluate(spool: .none) { stats in
            let hull = stats[Self.firstHull]
            let moduleID = hull.modules.ids(in: .hi).first { _ in true }!
            let module = hull.modules[moduleID]
            return (module.repair()?.hpPerSecond ?? 0,
                    module.attributes[.repairMultiplierBonusMax] ?? 0)
        }

        #expect(cold > 0, "a mutadaptive repairer must show up in Module.repair()")
        #expect(maxBonus > 0)

        let (hot, isRemote, kindIsArmor) = await engine.evaluate(spool: .full) { stats in
            let hull = stats[Self.firstHull]
            let moduleID = hull.modules.ids(in: .hi).first { _ in true }!
            let repair = hull.modules[moduleID].repair()!
            return (repair.hpPerSecond, repair.isRemote, repair.kind == .armor)
        }

        #expect(isRemote && kindIsArmor)
        #expect(abs(hot - cold * (1 + maxBonus)) < 1e-6,
                "full spool = x(1 + max): \(hot) vs \(cold * (1 + maxBonus))")
    }

    @Test("Incoming remote repair reaches the target tank already spooled")
    func mutadaptiveTankOfTarget() async throws {
        let engine = DogmaEngine()
        try await engine.edit { fit in
            let target = try fit.pilots.add(skillLevel: 5)
            let logi = try fit.pilots.add(skillLevel: 5)
            let targetHull = target.hull
            let logiHull = logi.hull
            
            try targetHull.set(typeID: .dominix)
            try logiHull.set(typeID: .rodiva)

            let repairer = try logiHull.modules.add(.heavyMutadaptiveRemoteArmorRepairerII)
            repairer.state = .active
            repairer.target = target.id.hull
        }

        func armorRepair(_ policy: SpoolPolicy) async -> Double {
            await engine.evaluate(spool: policy) { stats in
                stats[PilotID(1).hull].tank().armorRepair
            }
        }

        let cold = await armorRepair(.none)
        let hot = await armorRepair(.full)

        #expect(cold > 0, "remote repair must reach the target")
        #expect(hot > cold, "spool must raise incoming repair: \(hot) vs \(cold)")
    }
}
