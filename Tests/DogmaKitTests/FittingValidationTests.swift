//
//  FittingValidationTests.swift
//  DogmaKit
//
//  Validation on the write path (Fit.Hull.modules.add): rig size and subsystems.
//  Slot/CPU/PG overfitting is allowed (reported via SlotCapacity/Resource);
//  structurally impossible fits throw DogmaError.
//

import Testing
@testable import DogmaKit

@Suite("Fitting validation", .setupDebugNames)
struct FittingValidationTests {

    private static let firstHull = PilotID(1).hull

    private func makeFit(hull hullType: TypeID, modules: [TypeID]) async throws -> DogmaEngine {
        let engine = DogmaEngine()
        try await engine.edit { fit in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: hullType)
            for typeID in modules {
                try hull.modules.add(typeID)
            }
        }
        return engine
    }

    // MARK: - Rig size

    @Test("A rig of matching size fits")
    func matchingRigFits() async throws {
        let engine = try await makeFit(hull: .rifter, modules: [.smallTrimarkArmorPumpI])
        let (hullSize, rigSize, count) = await engine.evaluate { stats -> (RigSize, RigSize, Int) in
            let hull = stats[Self.firstHull]
            let ids = Array(hull.modules.ids(in: .rig))
            return (hull.rigSize, hull.modules[ids[0]].rigSize, ids.count)
        }
        #expect(count == 1)
        #expect(hullSize == .small)
        #expect(rigSize == hullSize)
    }

    @Test("An oversized rig does not fit")
    func oversizedRigDoesNotFit() async throws {
        await #expect(throws: DogmaError.self) {
            _ = try await self.makeFit(hull: .rifter, modules: [.mediumTrimarkArmorPumpI])
        }
    }

    @Test("An undersized rig does not fit")
    func undersizedRigDoesNotFit() async throws {
        await #expect(throws: DogmaError.self) {
            _ = try await self.makeFit(hull: .rupture, modules: [.smallTrimarkArmorPumpI])
        }
    }

    @Test("The rig size error carries both sizes")
    func rigSizeMismatchCarriesBothSizes() async throws {
        do {
            _ = try await makeFit(hull: .rupture, modules: [.smallTrimarkArmorPumpI])
            Issue.record("expected rigSizeMismatch")
        }
        catch let error as DogmaError {
            guard case let .rigSizeMismatch(typeID, expected, actual) = error else {
                Issue.record("expected rigSizeMismatch, got \(error)")
                return
            }
            #expect(typeID == .smallTrimarkArmorPumpI)
            #expect(expected == .medium)
            #expect(actual == .small)
        }
    }

    @Test("A hull without rigSize accepts no rigs")
    func hullWithoutRigSizeTakesNoRigs() async throws {
        // A capsule has neither rigSlots nor rigSize, so any sized rig is invalid.
        await #expect(throws: DogmaError.self) {
            _ = try await self.makeFit(hull: .capsule, modules: [.smallTrimarkArmorPumpI])
        }
    }

    @Test("Each rig size is compatible with exactly one hull size")
    func rigSizesAreMutuallyExclusive() async throws {
        let rigs: [(TypeID, RigSize)] = [
            (.smallTrimarkArmorPumpI, .small),
            (.mediumTrimarkArmorPumpI, .medium),
            (.largeTrimarkArmorPumpI, .large),
            (.capitalTrimarkArmorPumpI, .xLarge),
        ]
        // Rifter — small, Rupture — medium.
        for (hullType, hullSize) in [(TypeID.rifter, RigSize.small), (TypeID.rupture, RigSize.medium)] {
            for (rig, rigSize) in rigs {
                if rigSize == hullSize {
                    let engine = try await makeFit(hull: hullType, modules: [rig])
                    let count = await engine.evaluate { stats -> Int in
                        let hull = stats[Self.firstHull]
                        return hull.modules.count(in: .rig)
                    }
                    #expect(count == 1, "\(rig) must fit on \(hullType)")
                }
                else {
                    await #expect(throws: DogmaError.self, "\(rig) must not fit on \(hullType)") {
                        _ = try await self.makeFit(hull: hullType, modules: [rig])
                    }
                }
            }
        }
    }

    // MARK: - Subsystems

    @Test("A subsystem does not fit a hull without maxSubSystems")
    func subsystemNeedsSubsystemSlots() async throws {
        do {
            _ = try await makeFit(hull: .rifter, modules: [.tenguCoreAugmentedGravitonReactor])
            Issue.record("expected subsystemsNotSupported")
        }
        catch let error as DogmaError {
            guard case let .subsystemsNotSupported(hullType) = error else {
                Issue.record("expected subsystemsNotSupported, got \(error)")
                return
            }
            #expect(hullType == .rifter)
        }
    }

    @Test("The occupied-slot error names the conflicting subsystem")
    func occupiedSubsystemSlotNamesTheConflict() async throws {
        do {
            _ = try await makeFit(hull: .tengu, modules: [.tenguCoreAugmentedGravitonReactor,
                                                          .tenguCoreObfuscationManifold])
            Issue.record("expected subsystemSlotOccupied")
        }
        catch let error as DogmaError {
            guard case let .subsystemSlotOccupied(typeID, occupant) = error else {
                Issue.record("expected subsystemSlotOccupied, got \(error)")
                return
            }
            #expect(typeID == .tenguCoreObfuscationManifold)
            #expect(occupant == .tenguCoreAugmentedGravitonReactor)
        }
    }

    @Test("A subsystem of another strategic cruiser does not fit (canFit by fitsToShipType)")
    func subsystemOfAnotherStrategicCruiserDoesNotFit() async throws {
        // The Tengu Core slot is free, so only canFit can reject this.
        do {
            _ = try await makeFit(hull: .tengu, modules: [.legionCoreAugmentedAntimatterReactor])
            Issue.record("expected cantFit")
        }
        catch let error as DogmaError {
            guard case let .cantFit(typeID, hullType) = error else {
                Issue.record("expected cantFit, got \(error)")
                return
            }
            #expect(typeID == .legionCoreAugmentedAntimatterReactor)
            #expect(hullType == .tengu)
        }
    }

    @Test("Subsystem slots are independent: one of each kind fits together")
    func distinctSubsystemSlotsCoexist() async throws {
        let subsystems: [TypeID] = [.tenguCoreAugmentedGravitonReactor,
                                    .tenguDefensiveSupplementalScreening,
                                    .tenguOffensiveAcceleratedEjectionBay,
                                    .tenguPropulsionChassisOptimization]
        let engine = try await makeFit(hull: .tengu, modules: subsystems)
        let capacity = await engine.evaluate { stats -> SlotCapacity in
            stats[Self.firstHull].capacity(of: .subsystem)
        }
        #expect(capacity.used == subsystems.count)
        #expect(capacity.total == subsystems.count)
    }
}
