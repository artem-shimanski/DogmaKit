//
//  MutaplasmidTests.swift
//  DogmaKit
//
//  Mutaplasmids (abyssal / dynamic items).
//  Expectations are derived from the data itself (base value x mutaplasmid bounds), so
//  balance patches do not break the tests. Reference vector: Unstable 50MN Microwarpdrive
//  Mutaplasmid (47297) on 50MN Microwarpdrive I (12052) -> 50MN Abyssal Microwarpdrive (47408).
//

import Foundation
import Testing
@testable import DogmaKit

@Suite("Mutaplasmids", .setupDebugNames)
struct MutaplasmidTests {

    private static let pilot = EntityID.pilot(1)
    private static let hull = PilotID(1).hull

    /// A fit with one mutated module. Returns the engine and the module's EntityID.
    private func makeMutatedFit(hull hullType: TypeID = .rifter,
                                base: TypeID = ._50MNMicrowarpdriveI,
                                mutaplasmid: TypeID = .unstable50MNMicrowarpdriveMutaplasmid,
                                rolls: [(AttributeID, Double)] = []) async throws -> (DogmaEngine, ModuleID) {
        let engine = DogmaEngine()
        let moduleID = try await engine.edit { fit -> ModuleID in
            let pilot = try fit.pilots.add(skillLevel: 0)
            let hull = pilot.hull
            try hull.set(typeID: hullType)
            let module = try hull.modules.add(base, mutaplasmid: mutaplasmid)
            for (attributeID, value) in rolls {
                try module.setRoll(value, for: attributeID)
            }
            return module.id
        }
        return (engine, moduleID)
    }

    // MARK: - Data

    @Test("The mutaplasmid is imported: applicableTypes and ranges are present")
    func mutaplasmidIsImported() async throws {
        let engine = DogmaEngine()
        try await engine.edit { fit in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: .rifter)
        }
        let (resultingTypeID, applicable, notApplicable, rangeCount) = await engine.evaluate { stats -> (TypeID, Bool, Bool, Int) in
            let sde = stats.session.pointee.sde
            let mutaplasmid = sde.mutaplasmid(.unstable50MNMicrowarpdriveMutaplasmid)!
            return (mutaplasmid.resultingTypeID.load(),
                    mutaplasmid.applicableTypes.contains(._50MNMicrowarpdriveI),
                    mutaplasmid.applicableTypes.contains(.rifter),
                    mutaplasmid.ranges.count)
        }
        #expect(resultingTypeID == ._50MNAbyssalMicrowarpdrive)
        #expect(applicable)
        #expect(!notApplicable)
        #expect(rangeCount == 5)
    }

    // MARK: - Base values

    @Test("An unrolled mutated module equals the base: final type, base stats")
    func unrolledMutationMatchesBaseType() async throws {
        // Reference: the same module without mutation.
        let plain = DogmaEngine()
        try await plain.edit { fit in
            let pilot = try fit.pilots.add(skillLevel: 0)
            let hull = pilot.hull
            try hull.set(typeID: .rifter)
            try hull.modules.add(._50MNMicrowarpdriveI)
        }
        let (mutated, moduleID) = try await makeMutatedFit()

        let expected = await plain.evaluate { stats -> [Double] in
            let hull = stats[Self.hull]
            let module = hull.modules[hull.modules.ids(in: .med).first { _ in true }!]
            return [module.attributes[.speedFactor] ?? 0,
                    module.attributes[.cpu] ?? 0,
                    module.attributes[.capacitorNeed] ?? 0,
                    module.attributes[.signatureRadiusBonus] ?? 0]
        }
        let (actual, typeID, isMutated, baseTypeID) = await mutated.evaluate { stats -> ([Double], TypeID, Bool, TypeID?) in
            let hull = stats[Self.hull]
            let module = hull.modules[moduleID]
            return ([module.attributes[.speedFactor] ?? 0,
                     module.attributes[.cpu] ?? 0,
                     module.attributes[.capacitorNeed] ?? 0,
                     module.attributes[.signatureRadiusBonus] ?? 0],
                    module.typeID, module.isMutated, module.baseTypeID)
        }

        // The entity carries the FINAL type but the base values.
        #expect(typeID == ._50MNAbyssalMicrowarpdrive)
        #expect(isMutated)
        #expect(baseTypeID == ._50MNMicrowarpdriveI)
        #expect(expected.allSatisfy { $0 != 0 })
        #expect(actual == expected)
    }

    @Test("A roll replaces the base value; skills and penalties apply on top")
    func rollReplacesBaseValue() async throws {
        // The cpu bounds of 47297 are 0.8...1.5. Take the maximum.
        let (engine, moduleID) = try await makeMutatedFit()
        let (base, rolled) = await engine.evaluate { stats -> (Double, Double) in
            let hull = stats[Self.hull]
            let module = hull.modules[moduleID]
            var base = 0.0
            var maxValue = 0.0
            module.forEachRoll { roll in
                if roll.attributeID == .cpu {
                    base = roll.baseValue
                    maxValue = roll.maxValue
                }
            }
            return (base, maxValue)
        }
        #expect(base > 0)
        #expect(rolled > base)

        try await engine.edit { fit in
            try fit[moduleID].setRoll(rolled, for: .cpu)
        }
        let (value, multiplier) = await engine.evaluate { stats -> (Double, Double) in
            let hull = stats[Self.hull]
            let module = hull.modules[moduleID]
            var multiplier = 0.0
            module.forEachRoll { roll in
                if roll.attributeID == .cpu { multiplier = roll.multiplier }
            }
            return (module.attributes[.cpu] ?? 0, multiplier)
        }
        // The module's cpu has no skills/bonuses in this fit, so the value equals the roll.
        #expect(abs(value - rolled) < 1e-9 * rolled)
        #expect(abs(multiplier - rolled / base) < 1e-9)
    }

    @Test("A multiplier and an absolute value specify the same roll")
    func multiplierAndAbsoluteAgree() async throws {
        let (engine, moduleID) = try await makeMutatedFit()
        try await engine.edit { fit in
            try fit[moduleID].setRoll(multiplier: 1.1, for: .speedFactor)
        }
        let (value, base) = await engine.evaluate { stats -> (Double, Double) in
            var value = 0.0
            var base = 0.0
            let hull = stats[Self.hull]
            let module = hull.modules[moduleID]

            module.forEachRoll { roll in
                if roll.attributeID == .speedFactor { value = roll.value; base = roll.baseValue }
            }
            return (value, base)
        }
        #expect(abs(value - base * 1.1) < 1e-6 * base)
    }

    // MARK: - Clamping and validation

    @Test("A roll outside the bounds is clamped")
    func rollIsClampedToRange() async throws {
        let (engine, moduleID) = try await makeMutatedFit()
        let bounds = await engine.evaluate { stats -> [AttributeID: ClosedRange<Double>] in
            var bounds: [AttributeID: ClosedRange<Double>] = [:]
            let hull = stats[Self.hull]
            let module = hull.modules[moduleID]

            module.forEachRoll { roll in
                bounds[roll.attributeID] = roll.range
            }
            return bounds
        }
        let range = bounds[.speedFactor]!

        try await engine.edit { fit in
            let module = fit[moduleID]
            try module.setRoll(range.upperBound * 10, for: .speedFactor)
        }
        let high = await engine.evaluate { stats in
            let hull = stats[Self.hull]
            let module = hull.modules[moduleID]
            return module.attributes[.speedFactor] ?? 0
        }
        #expect(abs(high - range.upperBound) < 1e-6 * range.upperBound)

        try await engine.edit { fit in
            try fit[moduleID].setRoll(-1000, for: .speedFactor)
        }
        let low = await engine.evaluate { stats in
            let hull = stats[Self.hull]
            let module = hull.modules[moduleID]

            return module.attributes[.speedFactor] ?? 0
        }
        #expect(abs(low - range.lowerBound) < 1e-6 * range.lowerBound)
    }

    @Test("A roll on an attribute outside the mutaplasmid ranges is an error")
    func rollOnForeignAttributeThrows() async throws {
        let (engine, moduleID) = try await makeMutatedFit()
        await #expect(throws: DogmaError.self) {
            try await engine.edit { fit in
                // This mutaplasmid does not mutate maxVelocity.
                try fit[moduleID].setRoll(1, for: .maxVelocity)
            }
        }
    }

    @Test("An inapplicable mutaplasmid and a roll on an unmutated module are errors")
    func writePathValidation() async throws {
        let engine = DogmaEngine()
        await #expect(throws: DogmaError.self) {
            try await engine.edit { fit in
                let pilot = try fit.pilots.add(skillLevel: 5)
                let hull = pilot.hull
                try hull.set(typeID: .rifter)
                // The MWD mutaplasmid does not apply to an Ancillary Shield Booster.
                try hull.modules.add(.mediumAncillaryShieldBooster,
                                   mutaplasmid: .unstable50MNMicrowarpdriveMutaplasmid)
            }
        }
        await #expect(throws: DogmaError.self) {
            try await engine.edit { fit in
                let pilot = try fit.pilots.add(skillLevel: 5)
                let hull = pilot.hull
                try hull.set(typeID: .rifter)
                let module = try hull.modules.add(._50MNMicrowarpdriveI)
                try module.setRoll(1, for: .cpu)
            }
        }
    }

    // MARK: - Regressions for an empty final type

    @Test("A charge fits an abyssal Ancillary Shield Booster, forceReload is kept")
    func mutatedAncillaryShieldBoosterAcceptsCharge() async throws {
        let engine = DogmaEngine()
        let moduleID = try await engine.edit { fit -> ModuleID in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: .rifter)
            let module = try hull.modules.add(.mediumAncillaryShieldBooster,
                                                  mutaplasmid: .unstableMediumAncillaryShieldBoosterMutaplasmid)
            // Charge requirements (chargeGroup2 = Capacitor Booster Charge,
            // chargeSize = 1) must survive the mutation.
            try module.setCharge(.capBooster50)
            return module.id
        }
        let (typeID, hasCharge, hasChargeGroup, shieldBonus) = await engine.evaluate { stats -> (TypeID, Bool, Bool, Double) in
            let hull = stats[Self.hull]
            let module = hull.modules[moduleID]
            return (module.typeID,
                    module.charge != nil,
                    module.chargeGroup?.isEmpty == false,
                    module.attributes[.shieldBonus] ?? 0)
        }
        #expect(typeID == .mediumAbyssalAncillaryShieldBooster)
        #expect(hasCharge)
        #expect(hasChargeGroup)
        // shieldBonus is absent on the final type and comes from the base type.
        #expect(shieldBonus > 0)
    }

    @Test("A mutated drone deals damage (dealsDamage from the base type)")
    func mutatedDroneDealsDamage() async throws {
        let engine = DogmaEngine()
        let droneID = try await engine.edit { fit -> DroneID in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: .tristan)
            let drone = try hull.drones.add(.acolyteII, mutaplasmid: .exigentLightDroneFirepowerMutaplasmid)
            drone.isActive = true
            return drone.id
        }
        let (typeID, baseTypeID, dealsDamage, dps) = await engine.evaluate { stats -> (TypeID, TypeID?, Bool, DamageVector) in
            let hull = stats[Self.hull]
            let drone = hull.drones[droneID]
            return (drone.typeID, drone.baseTypeID, drone.dealsDamage, drone.dps())
        }
        #expect(typeID == .lightMutatedDrone)
        #expect(baseTypeID == .acolyteII)
        // Regression: Light Mutated Drone has neither emDamage nor damageMultiplier;
        // without a fallback to Acolyte II the flag and all damage would be zero.
        #expect(dealsDamage)
        #expect(dps != .zero)
    }

    // MARK: - Lifecycle

    @Test("mutate/demutate preserve state and leave no garbage")
    func mutateAndDemutateRoundTrip() async throws {
        let engine = DogmaEngine()
        let moduleID = try await engine.edit { fit -> ModuleID in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: .rifter)
            let module = try hull.modules.add(._50MNMicrowarpdriveI)
            module.state = .online
            return module.id
        }

        try await engine.edit { fit in
            try fit[moduleID].mutate(with: .unstable50MNMicrowarpdriveMutaplasmid)
        }
        let afterMutate = await engine.evaluate { stats -> (TypeID, Bool, Entity.Module.State) in
            let hull = stats[Self.hull]
            let module = hull.modules[moduleID]
            return (module.typeID, module.isMutated, module.state)
        }
        #expect(afterMutate.0 == ._50MNAbyssalMicrowarpdrive)
        #expect(afterMutate.1)
        #expect(afterMutate.2 == .online)

        try await engine.edit { fit in
            try fit[moduleID].demutate()
        }
        let afterDemutate = await engine.evaluate { stats -> (TypeID, Bool, Int) in
            let hull = stats[Self.hull]
            let module = hull.modules[moduleID]
            var rolls = 0
            module.forEachRoll { _ in rolls += 1 }
            return (module.typeID, module.isMutated, rolls)
        }
        #expect(afterDemutate.0 == ._50MNMicrowarpdriveI)
        #expect(!afterDemutate.1)
        #expect(afterDemutate.2 == 0)
    }

    @Test("mutate(with:rolls:) mutates and sets rolls in one call")
    func mutateWithRolls() async throws {
        let engine = DogmaEngine()
        let moduleID = try await engine.edit { fit -> ModuleID in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: .rifter)
            let module = try hull.modules.add(._50MNMicrowarpdriveI)
            // Deliberately extreme values; they must clamp to the mutaplasmid bounds.
            try module.mutate(with: .unstable50MNMicrowarpdriveMutaplasmid,
                              rolls: [(.cpu, 1e9), (.speedFactor, -1e9)])
            return module.id
        }
        let rolls = await engine.evaluate { stats -> [AttributeID: MutationRoll] in
            var rolls: [AttributeID: MutationRoll] = [:]
            let hull = stats[Self.hull]
            let module = hull.modules[moduleID]
            module.forEachRoll { rolls[$0.attributeID] = $0 }
            return rolls
        }
        #expect(rolls.count == 5)
        #expect(rolls[.cpu]!.value == rolls[.cpu]!.maxValue)
        #expect(rolls[.speedFactor]!.value == rolls[.speedFactor]!.minValue)
        // Attributes not listed stay at base values (multiplier 1.0).
        #expect(rolls[.capacitorNeed]!.value == rolls[.capacitorNeed]!.baseValue)
    }

    @Test("mutate(with:rolls:) is atomic: a foreign attribute does not leave the module mutated")
    func mutateWithRollsIsAtomic() async throws {
        let engine = DogmaEngine()
        let moduleID = try await engine.edit { fit -> ModuleID in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: .rifter)
            return try hull.modules.add(._50MNMicrowarpdriveI).id
        }
        await #expect(throws: DogmaError.self) {
            try await engine.edit { fit in
                // This mutaplasmid does not mutate maxVelocity, so it errors before mutating.
                try fit[moduleID].mutate(with: .unstable50MNMicrowarpdriveMutaplasmid,
                                                rolls: [(.cpu, 45), (.maxVelocity, 1)])
            }
        }
        let (typeID, isMutated) = await engine.evaluate { stats -> (TypeID, Bool) in
            let hull = stats[Self.hull]
            let module = hull.modules[moduleID]
            return (module.typeID, module.isMutated)
        }
        #expect(typeID == ._50MNMicrowarpdriveI)
        #expect(!isMutated)
    }

    @Test("EntityID is reused: a new module in the same slot does not inherit rolls")
    func removedMutationDoesNotLeak() async throws {
        let engine = DogmaEngine()
        let (firstID, secondID) = try await engine.edit { fit -> (ModuleID, ModuleID) in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: .rifter)
            let mutated = try hull.modules.add(._50MNMicrowarpdriveI,
                                                   mutaplasmid: .unstable50MNMicrowarpdriveMutaplasmid)
            let firstID = mutated.id
            try mutated.setRoll(multiplier: 1.5, for: .cpu)
            mutated.remove()
            let plain = try hull.modules.add(._50MNMicrowarpdriveI)
            return (firstID, plain.id)
        }
        // Slots come from a free list so the ID must match, otherwise the test
        // does not check what is intended.
        #expect(firstID == secondID)

        let (isMutated, rolls) = await engine.evaluate { stats -> (Bool, Int) in
            let hull = stats[Self.hull]
            let module = hull.modules[secondID]
            var rolls = 0
            module.forEachRoll { _ in rolls += 1 }
            return (module.isMutated, rolls)
        }
        #expect(!isMutated)
        #expect(rolls == 0)
    }
}
