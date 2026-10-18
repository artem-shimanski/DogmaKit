//
//  EnvironmentTests.swift
//  DogmaKit
//
//  Environment effects (`Fit.environment`): wormhole effects, abyssal weather, Triglavian
//  storms. They apply to ALL ships of the session at once: their modifiers use the
//  `shipID`/`charID` domain, which `Domain.resolve` expands to every hull and pilot for an
//  `Entity.Kind.environment` entity.
//
//  SDE numbers are not hardcoded; "before" and "after" are compared.
//

import Testing
@testable import DogmaKit

@Suite("Environment", .setupDebugNames)
struct EnvironmentTests {

    private static let first = PilotID(1).hull
    private static let second = PilotID(2).hull

    private func makeEngine(environment: [TypeID] = [],
                            pilots: Int = 1) async throws -> DogmaEngine {
        let engine = DogmaEngine()
        try await engine.edit { fit in
            for typeID in environment {
                try fit.environment.add(typeID)
            }
            for _ in 0..<pilots {
                let pilot = try fit.pilots.add(skillLevel: 5)
                try pilot.hull.set(typeID: .rifter)
            }
        }
        return engine
    }

    // MARK: - Calculation

    @Test("Wolf-Rayet raises ship armor")
    func wolfRayetBoostsArmor() async throws {
        let plain = try await makeEngine()
        let boosted = try await makeEngine(environment: [.class6WolfRayetEffects])

        let base = await plain.evaluate { $0[Self.first].attributes[.armorHP] ?? 0 }
        let withEffect = await boosted.evaluate { $0[Self.first].attributes[.armorHP] ?? 0 }

        #expect(base > 0)
        #expect(withEffect > base)
    }

    @Test("An environment effect applies to every ship, not just the first")
    func environmentAppliesToEveryHull() async throws {
        let plain = try await makeEngine(pilots: 2)
        let boosted = try await makeEngine(environment: [.class6WolfRayetEffects], pilots: 2)

        let (base1, base2) = await plain.evaluate {
            ($0[Self.first].attributes[.armorHP] ?? 0, $0[Self.second].attributes[.armorHP] ?? 0)
        }
        let (boosted1, boosted2) = await boosted.evaluate {
            ($0[Self.first].attributes[.armorHP] ?? 0, $0[Self.second].attributes[.armorHP] ?? 0)
        }

        #expect(boosted1 > base1)
        #expect(boosted2 > base2)
        // Both ships are identical, so the bonus must be identical: the environment
        // has no pilot of its own and must not favour the first one.
        #expect(boosted1 == boosted2)
    }

    @Test("Removing the environment restores the original stats")
    func removingEnvironmentRestoresStats() async throws {
        let engine = try await makeEngine()
        let base = await engine.evaluate { $0[Self.first].attributes[.armorHP] ?? 0 }

        try await engine.edit { fit in
            try fit.environment.add(.class6WolfRayetEffects)
        }
        let boosted = await engine.evaluate { $0[Self.first].attributes[.armorHP] ?? 0 }

        await engine.edit { fit in
            fit.environment.removeAll()
        }
        let restored = await engine.evaluate { $0[Self.first].attributes[.armorHP] ?? 0 }

        #expect(boosted > base)
        #expect(restored == base)
    }

    // MARK: - Model

    @Test("The environment has its own ID space and does not collide with pilots")
    func environmentHasOwnIDSpace() async throws {
        let engine = try await makeEngine(environment: [.class1PulsarEffects, .class1BlackHoleEffects],
                                          pilots: 2)
        let (environmentCount, pilotCount, types) = await engine.evaluate { stats -> (Int, Int, Set<UInt32>) in
            var types = Set<UInt32>()
            for id in stats.environment.allIDs {
                types.insert(stats[id].typeID.rawValue)
            }
            return (stats.environment.count, stats.pilots.count, types)
        }
        #expect(environmentCount == 2)
        #expect(pilotCount == 2)
        #expect(types == [TypeID.class1PulsarEffects.rawValue, TypeID.class1BlackHoleEffects.rawValue])
    }

    @Test("A ship cannot be placed in the environment")
    func onlyCelestialTypesAllowed() async throws {
        let engine = DogmaEngine()
        await #expect(throws: DogmaError.self) {
            try await engine.edit { fit in
                try fit.environment.add(.rifter)
            }
        }
    }
}
