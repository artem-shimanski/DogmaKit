//
//  StackingPenaltyTests.swift
//  DogmaKit
//
//  Stacking penalty tests.
//
//  The n-th strongest modifier is scaled by exp(-n² / 7.1289), counting from 0. Multipliers
//  above and below 1 form two independent chains, each capped at 10 entries. Penalties are
//  grouped per (target, operation). Bonus magnitudes are measured on a single-module fit
//  rather than hardcoded.
//

import Testing
import Foundation
@testable import DogmaKit

@Suite("Stacking penalty", .setupDebugNames)
struct StackingPenaltyTests {

    private static let firstHull = PilotID(1).hull

    /// Penalty coefficient for the modifier at `index`.
    private static func penalty(_ index: Int) -> Double {
        exp(-pow(Double(index), 2) / 7.1289)
    }

    /// Size of the penalty table.
    private static let penaltyTableSize = 10

    /// Reference implementation: two independent chains (>= 1 descending, < 1 ascending), each capped at 10.
    private static func stacked(base: Double, multipliers: [Double]) -> Double {
        var value = base
        for (index, m) in multipliers.filter({ $0 < 1 }).sorted(by: <).enumerated()
        where index < penaltyTableSize {
            value *= 1 + (m - 1) * penalty(index)
        }
        for (index, m) in multipliers.filter({ $0 >= 1 }).sorted(by: >).enumerated()
        where index < penaltyTableSize {
            value *= 1 + (m - 1) * penalty(index)
        }
        return value
    }

    /// A Rifter with the given modules, all online.
    private func makeFit(_ modules: [(TypeID, Int)]) async throws -> DogmaEngine {
        let engine = DogmaEngine()
        try await engine.edit { fit in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: .rifter)
            for (typeID, count) in modules {
                for _ in 0..<count {
                    let module = try hull.modules.add(typeID)
                    module.state = .online
                }
            }
        }
        return engine
    }

    private func hullAttribute(_ engine: DogmaEngine, _ attribute: AttributeID) async -> Double {
        await engine.evaluate { stats in
            stats[Self.firstHull].attributes[attribute, default: .sde]
        }
    }

    /// Hull attribute value for a fit of `count` identical modules.
    private func value(of attribute: AttributeID, with typeID: TypeID, count: Int) async throws -> Double {
        let engine = try await makeFit(count > 0 ? [(typeID, count)] : [])
        return await hullAttribute(engine, attribute)
    }

    /// Relative-tolerance comparison.
    private func isClose(_ actual: Double, _ expected: Double, relative tolerance: Double = 1e-9) -> Bool {
        abs(actual - expected) <= tolerance * max(abs(expected), 1)
    }

    // MARK: - Increasing chain (multipliers > 1)

    @Test("N identical Overdrives: maxVelocity matches the penalty formula",
          arguments: [2, 3, 4, 5, 6])
    func identicalModifiersFollowPenaltyFormula(count: Int) async throws {
        let base = try await value(of: .maxVelocity, with: .overdriveInjectorSystemII, count: 0)
        let single = try await value(of: .maxVelocity, with: .overdriveInjectorSystemII, count: 1)
        #expect(base > 0)
        #expect(single > base, "Overdrive must boost velocity")

        // The first modifier in a chain is unpenalized, so one module gives the raw multiplier.
        let multiplier = single / base

        let actual = try await value(of: .maxVelocity, with: .overdriveInjectorSystemII, count: count)
        let expected = Self.stacked(base: base, multipliers: Array(repeating: multiplier, count: count))
        #expect(isClose(actual, expected), "count = \(count): actual = \(actual), expected = \(expected)")
    }

    @Test("The penalty is applied: result is below naive multiplication")
    func penaltyIsActuallyApplied() async throws {
        let base = try await value(of: .maxVelocity, with: .overdriveInjectorSystemII, count: 0)
        let single = try await value(of: .maxVelocity, with: .overdriveInjectorSystemII, count: 1)
        let triple = try await value(of: .maxVelocity, with: .overdriveInjectorSystemII, count: 3)

        let multiplier = single / base
        #expect(triple < base * pow(multiplier, 3))
        #expect(triple > single)
    }

    @Test("Each further identical module adds less")
    func incrementsAreDiminishing() async throws {
        var values: [Double] = []
        for count in 0...5 {
            values.append(try await value(of: .maxVelocity, with: .overdriveInjectorSystemII, count: count))
        }
        let increments = zip(values.dropFirst(), values).map { $0 - $1 }
        #expect(increments.allSatisfy { $0 > 0 })
        for (next, previous) in zip(increments.dropFirst(), increments) {
            #expect(next < previous)
        }
    }

    @Test("The strongest modifier gets penalty index 0")
    func strongestModifierIsPenalizedFirst() async throws {
        let base = try await value(of: .maxVelocity, with: .overdriveInjectorSystemII, count: 0)
        let t2 = try await value(of: .maxVelocity, with: .overdriveInjectorSystemII, count: 1)
        let t1 = try await value(of: .maxVelocity, with: .overdriveInjectorSystemI, count: 1)
        #expect(t2 > t1, "T2 Overdrive must be stronger than T1")

        let m2 = t2 / base
        let m1 = t1 / base

        let engine = try await makeFit([(.overdriveInjectorSystemII, 1), (.overdriveInjectorSystemI, 1)])
        let actual = await hullAttribute(engine, .maxVelocity)

        // Strong one unpenalized, weak one with penalty(1).
        let expected = base * (1 + (m2 - 1) * Self.penalty(0)) * (1 + (m1 - 1) * Self.penalty(1))
        #expect(isClose(actual, expected), "actual = \(actual), expected = \(expected)")

        // Differs from the reverse assignment.
        let swapped = base * (1 + (m1 - 1) * Self.penalty(0)) * (1 + (m2 - 1) * Self.penalty(1))
        #expect(abs(expected - swapped) > 1e-6)
    }

    @Test("Fit order does not affect the result")
    func fitOrderDoesNotMatter() async throws {
        let a = try await makeFit([(.overdriveInjectorSystemI, 1), (.overdriveInjectorSystemII, 1)])
        let b = try await makeFit([(.overdriveInjectorSystemII, 1), (.overdriveInjectorSystemI, 1)])
        let va = await hullAttribute(a, .maxVelocity)
        let vb = await hullAttribute(b, .maxVelocity)
        #expect(isClose(va, vb), "\(va) != \(vb)")
    }

    // MARK: - Decreasing chain (multipliers < 1)

    @Test("Inertial Stabilizers: penalty on the chain of multipliers < 1",
          arguments: [2, 3, 4])
    func penaltyOnDecreasingChain(count: Int) async throws {
        let base = try await value(of: .agility, with: .inertialStabilizersII, count: 0)
        let single = try await value(of: .agility, with: .inertialStabilizersII, count: 1)
        #expect(base > 0)
        #expect(single < base, "Inertial Stabilizers must reduce agility")

        let multiplier = single / base
        #expect(multiplier < 1)

        let actual = try await value(of: .agility, with: .inertialStabilizersII, count: count)
        let expected = Self.stacked(base: base, multipliers: Array(repeating: multiplier, count: count))
        #expect(isClose(actual, expected), "count = \(count): actual = \(actual), expected = \(expected)")
    }

    // MARK: - Penalty table limits

    @Test("Modifiers beyond the top 10 are dropped")
    func penaltyTableIsCappedAtTen() async throws {
        let ten = try await value(of: .maxVelocity, with: .overdriveInjectorSystemII, count: 10)
        let eleven = try await value(of: .maxVelocity, with: .overdriveInjectorSystemII, count: 11)
        let twelve = try await value(of: .maxVelocity, with: .overdriveInjectorSystemII, count: 12)
        // The 11th and 12th modules fall outside the table, so the value is unchanged.
        #expect(eleven == ten)
        #expect(twelve == ten)

        let nine = try await value(of: .maxVelocity, with: .overdriveInjectorSystemII, count: 9)
        #expect(ten > nine, "the 10th module must still count")
    }

    // MARK: - Not penalized

    @Test("Additive bonuses stack linearly without a penalty",
          arguments: [2, 3, 4, 5])
    func additiveBonusesAreNotPenalized(count: Int) async throws {
        let base = try await value(of: .shieldCapacity, with: .largeShieldExtenderII, count: 0)
        let single = try await value(of: .shieldCapacity, with: .largeShieldExtenderII, count: 1)
        #expect(base > 0)
        #expect(single > base)

        let delta = single - base
        let actual = try await value(of: .shieldCapacity, with: .largeShieldExtenderII, count: count)
        #expect(isClose(actual, base + delta * Double(count)), "count = \(count): actual = \(actual), expected = \(base + delta * Double(count))")
    }

    @Test("The penalty is computed per attribute")
    func penaltyIsPerAttribute() async throws {
        // Shield extenders do not affect velocity and must not take penalty indices.
        let velocityOnly = try await makeFit([(.overdriveInjectorSystemII, 2)])
        let mixed = try await makeFit([(.overdriveInjectorSystemII, 2), (.largeShieldExtenderII, 3)])

        let a = await hullAttribute(velocityOnly, .maxVelocity)
        let b = await hullAttribute(mixed, .maxVelocity)
        #expect(isClose(a, b), "\(a) != \(b)")
    }

    @Test("Skills are not penalized and do not take module penalty indices")
    func skillsAreNotPenalized() async throws {
        // Skill bonuses are unpenalized, so the module multiplier is the same at any skill level.
        func multiplier(skillLevel: UInt8) async throws -> Double {
            func velocity(_ overdrives: Int) async throws -> Double {
                let engine = DogmaEngine()
                try await engine.edit { fit in
                    let pilot = try fit.pilots.add(skillLevel: skillLevel)
                    let hull = pilot.hull
                    try hull.set(typeID: .rifter)
                    for _ in 0..<overdrives {
                        let module = try hull.modules.add(.overdriveInjectorSystemII)
                        module.state = .online
                    }
                }
                return await hullAttribute(engine, .maxVelocity)
            }
            let withModules = try await velocity(3)
            let without = try await velocity(0)
            return withModules / without
        }

        let trained = try await multiplier(skillLevel: 5)
        let untrained = try await multiplier(skillLevel: 0)
        #expect(trained > 1)
        #expect(isClose(trained, untrained), "\(trained) != \(untrained)")
    }

    @Test("An offline module is not part of the penalty chain")
    func offlineModuleIsNotCounted() async throws {
        let twoOnline = try await makeFit([(.overdriveInjectorSystemII, 2)])
        let expected = await hullAttribute(twoOnline, .maxVelocity)

        let withOffline = DogmaEngine()
        try await withOffline.edit { fit in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: .rifter)
            for _ in 0..<2 {
                let module = try hull.modules.add(.overdriveInjectorSystemII)
                module.state = .online
            }
            // The third stays offline; it must not shift the others' indices.
            let module = try hull.modules.add(.overdriveInjectorSystemII)
            module.state = .offline
        }
        let actual = await hullAttribute(withOffline, .maxVelocity)
        #expect(isClose(actual, expected), "actual = \(actual), expected = \(expected)")
    }

    @Test("The penalty is stable across repeated calculations")
    func penaltyIsStableAcrossCalculations() async throws {
        let engine = try await makeFit([(.overdriveInjectorSystemII, 4)])
        let a = await hullAttribute(engine, .maxVelocity)
        let b = await hullAttribute(engine, .maxVelocity)
        let c = await hullAttribute(engine, .maxVelocity)
        #expect(a == b)
        #expect(b == c)
    }
}
