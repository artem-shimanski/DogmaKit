//
//  StrategicCruiserTests.swift
//  DogmaKit
//
//  Strategic cruiser (T3C) tests.
//
//  A T3C gets its slots, hardpoints and CPU/PG from its four subsystems, whose effects
//  are passive and not stacking-penalized. Expectations are derived from the subsystems'
//  own attributes rather than hardcoded SDE numbers.
//

import Testing
@testable import DogmaKit

@Suite("Strategic cruisers (T3C)", .setupDebugNames)
struct StrategicCruiserTests {

    /// A full Tengu subsystem set: Core / Defensive / Offensive / Propulsion.
    static let tenguSubsystems: [TypeID] = [
        .tenguCoreAugmentedGravitonReactor,
        .tenguDefensiveSupplementalScreening,
        .tenguOffensiveAcceleratedEjectionBay,
        .tenguPropulsionChassisOptimization,
    ]

    private static let firstHull = PilotID(1).hull

    /// Builds a Tengu with the given subsystems; their state is left offline (effects are passive).
    private func makeTengu(subsystems: [TypeID], modules: [TypeID] = []) async throws -> DogmaEngine {
        let engine = DogmaEngine()
        try await engine.edit { fit in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: .tengu)
            for typeID in subsystems {
                try hull.modules.add(typeID)
            }
            for typeID in modules {
                let module = try hull.modules.add(typeID)
                module.state = .online
            }
        }
        return engine
    }

    // MARK: - Subsystem fitting

    @Test("A subsystem goes into the subsystem slot, not hi/med/low")
    func subsystemGoesToSubsystemSlot() async throws {
        let engine = try await makeTengu(subsystems: Self.tenguSubsystems)
        let counts = await engine.evaluate { stats -> [Int] in
            let hull = stats[Self.firstHull]
            return Entity.Module.Slot.allCases.map { hull.modules.count(in: $0) }
        }
        for slot in Entity.Module.Slot.allCases {
            let expected = slot == .subsystem ? 4 : 0
            #expect(counts[Int(slot.rawValue)] == expected, "slot \(slot)")
        }
    }

    @Test("A T3C has exactly 4 subsystem slots")
    func fourSubsystemSlots() async throws {
        let engine = try await makeTengu(subsystems: Self.tenguSubsystems)
        let capacity = await engine.evaluate { stats -> SlotCapacity in
            stats[Self.firstHull].capacity(of: .subsystem)
        }
        #expect(capacity.total == 4)
        #expect(capacity.used == 4)
        #expect(capacity.available == 0)
    }

    @Test("A second subsystem in an occupied slot does not fit")
    func duplicateSubsystemSlotDoesNotFit() async throws {
        // Obfuscation Manifold is also a Core subsystem; the Core slot is already taken.
        await #expect(throws: DogmaError.self) {
            _ = try await self.makeTengu(subsystems: Self.tenguSubsystems + [.tenguCoreObfuscationManifold])
        }
    }

    @Test("A full set occupies 4 distinct subsystem slots")
    func subsystemsOccupyDistinctSlots() async throws {
        let engine = try await makeTengu(subsystems: Self.tenguSubsystems)
        let slots = await engine.evaluate { stats -> [Entity.Module.SubsystemSlot?] in
            let hull = stats[Self.firstHull]
            var result: [Entity.Module.SubsystemSlot?] = []
            hull.modules.forEach(in: .subsystem) { result.append($0.subsystemSlot) }
            return result
        }
        #expect(slots.count == 4)
        #expect(slots.allSatisfy { $0 != nil })
        #expect(Set(slots.compactMap { $0 }) == Set(Entity.Module.SubsystemSlot.allCases))
    }

    @Test("A subsystem of another hull does not fit")
    func subsystemOfAnotherHullDoesNotFit() async throws {
        let engine = DogmaEngine()
        await #expect(throws: DogmaError.self) {
            try await engine.edit { fit in
                let pilot = try fit.pilots.add(skillLevel: 5)
                let hull = pilot.hull
                try hull.set(typeID: .tengu)
                // A Legion subsystem on a Tengu is invalid.
                try hull.modules.add(.legionCoreAugmentedAntimatterReactor)
            }
        }
    }

    @Test("A subsystem does not fit on a regular ship")
    func subsystemDoesNotFitOnRegularShip() async throws {
        let engine = DogmaEngine()
        await #expect(throws: DogmaError.self) {
            try await engine.edit { fit in
                let pilot = try fit.pilots.add(skillLevel: 5)
                let hull = pilot.hull
                try hull.set(typeID: .rifter)
                try hull.modules.add(.tenguCoreAugmentedGravitonReactor)
            }
        }
    }

    // MARK: - Subsystems grant slots

    @Test("A bare T3C has no hi/med/low slots")
    func bareHullHasNoSlots() async throws {
        let engine = try await makeTengu(subsystems: [])
        let totals = await engine.evaluate { stats -> [Int] in
            let hull = stats[Self.firstHull]
            return [hull.capacity(of: .hi).total,
                    hull.capacity(of: .med).total,
                    hull.capacity(of: .low).total]
        }
        #expect(totals == [0, 0, 0])
    }

    @Test("Hull slots equal base plus the sum of subsystem slot modifiers")
    func slotsAreSumOfSubsystemModifiers() async throws {
        let bare = try await makeTengu(subsystems: [])
        let base = await bare.evaluate { stats -> [Int] in
            let hull = stats[Self.firstHull]
            return [hull.capacity(of: .hi).total,
                    hull.capacity(of: .med).total,
                    hull.capacity(of: .low).total]
        }

        let engine = try await makeTengu(subsystems: Self.tenguSubsystems)
        let (actual, expected) = await engine.evaluate { stats -> ([Int], [Int]) in
            let hull = stats[Self.firstHull]
            var hi = 0.0, med = 0.0, low = 0.0
            hull.modules.forEach(in: .subsystem) { subsystem in
                hi += subsystem.attributes[.hiSlotModifier] ?? 0
                med += subsystem.attributes[.medSlotModifier] ?? 0
                low += subsystem.attributes[.lowSlotModifier] ?? 0
            }
            return ([hull.capacity(of: .hi).total,
                     hull.capacity(of: .med).total,
                     hull.capacity(of: .low).total],
                    [base[0] + Int(hi), base[1] + Int(med), base[2] + Int(low)])
        }

        #expect(expected[0] > 0, "subsystems must grant hi slots")
        #expect(actual == expected)
    }

    @Test("Hull hardpoints equal base plus the sum of subsystem hardpoint modifiers")
    func hardpointsAreSumOfSubsystemModifiers() async throws {
        let bare = try await makeTengu(subsystems: [])
        let base = await bare.evaluate { stats -> [Int] in
            let hull = stats[Self.firstHull]
            return [hull.capacity(of: .launcher).total, hull.capacity(of: .turret).total]
        }

        let engine = try await makeTengu(subsystems: Self.tenguSubsystems)
        let (actual, expected) = await engine.evaluate { stats -> ([Int], [Int]) in
            let hull = stats[Self.firstHull]
            var launcher = 0.0, turret = 0.0
            hull.modules.forEach(in: .subsystem) { subsystem in
                launcher += subsystem.attributes[.launcherHardPointModifier] ?? 0
                turret += subsystem.attributes[.turretHardPointModifier] ?? 0
            }
            return ([hull.capacity(of: .launcher).total, hull.capacity(of: .turret).total],
                    [base[0] + Int(launcher), base[1] + Int(turret)])
        }

        #expect(expected[0] > 0)
        #expect(actual == expected)
    }

    @Test("Hull CPU/PG come from subsystems")
    func fittingResourcesComeFromSubsystems() async throws {
        let bare = try await makeTengu(subsystems: [])
        let (baseCPU, basePG) = await bare.evaluate { stats -> (Double, Double) in
            let hull = stats[Self.firstHull]
            return (hull.cpu.total, hull.powerGrid.total)
        }

        let engine = try await makeTengu(subsystems: Self.tenguSubsystems)
        let (cpu, pg) = await engine.evaluate { stats -> (Double, Double) in
            let hull = stats[Self.firstHull]
            return (hull.cpu.total, hull.powerGrid.total)
        }

        #expect(cpu > baseCPU)
        #expect(pg > basePG)
    }

    // MARK: - Subsystem states and effects

    @Test("A subsystem cannot go online: effective state is clamped to offline")
    func subsystemStateClampedToOffline() async throws {
        let engine = DogmaEngine()
        try await engine.edit { fit in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: .tengu)
            let subsystem = try hull.modules.add(.tenguOffensiveAcceleratedEjectionBay)
            // Requesting active must be demoted: maxAllowedState is .offline.
            subsystem.state = .active
        }
        let (requested, effective, hiSlots) = await engine.evaluate { stats -> (Entity.Module.State, Entity.Module.State, Int) in
            let hull = stats[Self.firstHull]
            let id = Array(hull.modules.ids(in: .subsystem))[0]
            let module = hull.modules[id]
            return (module.state, module.effectiveState, hull.capacity(of: .hi).total)
        }
        #expect(requested == .active)
        #expect(effective == .offline)
        // Passive bonuses still apply.
        #expect(hiSlots > 0)
    }

    // MARK: - Full fit

    @Test("Modules fit into subsystem-granted slots")
    func modulesFitIntoSubsystemGrantedSlots() async throws {
        let engine = try await makeTengu(subsystems: Self.tenguSubsystems,
                                         modules: [.largeShieldExtenderII, .damageControlII])
        let (med, low, medFree, lowFree) = await engine.evaluate { stats -> (Int, Int, Int, Int) in
            let hull = stats[Self.firstHull]
            return (hull.modules.count(in: .med), hull.modules.count(in: .low),
                    hull.capacity(of: .med).available, hull.capacity(of: .low).available)
        }
        #expect(med == 1)
        #expect(low == 1)
        #expect(medFree >= 0)
        #expect(lowFree >= 0)
    }

    @Test("A full T3C fit evaluates stably")
    func fullFitIsStable() async throws {
        let engine = try await makeTengu(subsystems: Self.tenguSubsystems,
                                         modules: [.largeShieldExtenderII, .damageControlII, .overdriveInjectorSystemII])
        func snapshot(_ engine: DogmaEngine) async -> [Double] {
            await engine.evaluate { stats -> [Double] in
                let hull = stats[Self.firstHull]
                return [hull.hitPoints.shield, hull.hitPoints.armor, hull.hitPoints.hull,
                        hull.attributes[.maxVelocity, default: .sde],
                        hull.cpu.total, hull.powerGrid.total]
            }
        }
        let a = await snapshot(engine)
        let b = await snapshot(engine)
        #expect(a == b)
        #expect(a.allSatisfy { $0 > 0 })
    }

    @Test("All four T3Cs build with their subsystems")
    func allStrategicCruisersFit() async throws {
        let fits: [(TypeID, [TypeID])] = [
            (.tengu, StrategicCruiserTests.tenguSubsystems),
            (.legion, [.legionCoreAugmentedAntimatterReactor,
                       .legionDefensiveAugmentedPlating,
                       .legionOffensiveAssaultOptimization,
                       .legionPropulsionIntercalatedNanofibers]),
            (.proteus, [.proteusCoreAugmentedFusionReactor,
                        .proteusDefensiveAugmentedPlating,
                        .proteusOffensiveHybridEncodingPlatform,
                        .proteusPropulsionHyperspatialOptimization]),
            (.loki, [.lokiCoreAugmentedNuclearReactor,
                     .lokiDefensiveAugmentedDurability,
                     .lokiOffensiveProjectileScopingArray,
                     .lokiPropulsionIntercalatedNanofibers]),
        ]

        for (hullType, subsystems) in fits {
            let engine = DogmaEngine()
            try await engine.edit { fit in
                let pilot = try fit.pilots.add(skillLevel: 5)
                let hull = pilot.hull
                try hull.set(typeID: hullType)
                for typeID in subsystems {
                    try hull.modules.add(typeID)
                }
            }
            let (subsystemCount, slots) = await engine.evaluate { stats -> (Int, Int) in
                let hull = stats[PilotID(1).hull]
                return (hull.modules.count(in: .subsystem),
                        hull.capacity(of: .hi).total + hull.capacity(of: .med).total + hull.capacity(of: .low).total)
            }
            #expect(subsystemCount == 4, "\(hullType)")
            #expect(slots > 0, "\(hullType): subsystems must grant slots")
        }
    }
}
