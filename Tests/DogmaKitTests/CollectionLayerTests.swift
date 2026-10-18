//
//  CollectionLayerTests.swift
//  DogmaKit
//
//  Collection layer between owner and element: Fit.Pilots/Modules/Drones/
//  Skills/Implants/Boosters and their FitStats mirrors.
//

import Testing
@testable import DogmaKit

@Suite("Collection layer", .setupDebugNames)
struct CollectionLayerTests {

    private static let firstPilot = PilotID(1)

    // Implants in three different slots (Perception / Memory / Willpower).
    private static let implants: [TypeID] = [.limitedOcularFilter,
                                            .limitedMemoryAugmentation,
                                            .limitedNeuralBoost]

    // MARK: - Implants

    @Test("Implants go to their own slots; count and subscript(slot:) agree")
    func implantsGoToOwnSlots() async throws {
        let engine = DogmaEngine()
        let slots: [UInt16] = try await engine.edit { fit -> [UInt16] in
            let pilot = try fit.pilots.add(skillLevel: 0)
            var slots: [UInt16] = []
            for typeID in Self.implants {
                let implant = try pilot.implants.add(typeID)
                slots.append(implant.slot)
            }
            return slots
        }
        // Slots must differ, otherwise the next check is meaningless.
        #expect(Set(slots).count == Self.implants.count)

        let (count, typeIDsBySlot) = await engine.evaluate { stats -> (Int, [TypeID?]) in
            let pilot = stats.pilots[Self.firstPilot]
            return (pilot.implants.count, slots.map { pilot.implants[slot: $0]?.typeID })
        }
        #expect(count == Self.implants.count)
        #expect(typeIDsBySlot == Self.implants.map { Optional($0) })
    }

    @Test("A second implant in an occupied slot throws")
    func implantSlotConflictThrows() async throws {
        let engine = DogmaEngine()
        await #expect(throws: DogmaError.self) {
            try await engine.edit { fit in
                let pilot = try fit.pilots.add(skillLevel: 0)
                try pilot.implants.add(.limitedOcularFilter)
                try pilot.implants.add(.limitedOcularFilterBeta)
            }
        }
    }

    // MARK: - Boosters

    @Test("Boosters and implants live in separate allocators")
    func boostersAndImplantsDoNotMix() async throws {
        let engine = DogmaEngine()
        let (boosterSlot, boosterType) = try await engine.edit { fit -> (UInt16, TypeID) in
            let pilot = try fit.pilots.add(skillLevel: 0)
            try pilot.implants.add(.limitedOcularFilter)
            let booster = try pilot.boosters.add(.standardCrashBooster)
            return (booster.slot, booster.typeID)
        }

        let (implantCount, boosterCount, foundType) = await engine.evaluate { stats -> (Int, Int, TypeID?) in
            let pilot = stats.pilots[Self.firstPilot]
            return (pilot.implants.count,
                    pilot.boosters.count,
                    pilot.boosters[slot: boosterSlot]?.typeID)
        }
        // A booster must not leak into the implants collection or vice versa.
        #expect(implantCount == 1)
        #expect(boosterCount == 1)
        #expect(foundType == boosterType)
    }

    @Test("A second booster in an occupied slot throws")
    func boosterSlotConflictThrows() async throws {
        let engine = DogmaEngine()
        await #expect(throws: DogmaError.self) {
            try await engine.edit { fit in
                let pilot = try fit.pilots.add(skillLevel: 0)
                try pilot.boosters.add(.standardCrashBooster)
                try pilot.boosters.add(.improvedCrashBooster)
            }
        }
    }

    // MARK: - Skills

    @Test("pilots.add creates every SDE skill at the given level")
    func pilotAddCreatesAllSkills() async throws {
        let engine = DogmaEngine()
        try await engine.edit { fit in
            try fit.pilots.add(skillLevel: 4)
        }
        let (count, gunnery) = await engine.evaluate { stats -> (Int, UInt8?) in
            let pilot = stats.pilots[Self.firstPilot]
            let skills = pilot.skills
            return (skills.count, skills[typeID: .gunnery]?.level)
        }
        #expect(count > 0)
        #expect(gunnery == 4)
    }

    @Test("setAll and setLevels change levels visible through subscript(typeID:)")
    func skillLevelWrites() async throws {
        let engine = DogmaEngine()
        try await engine.edit { fit in
            let pilot = try fit.pilots.add(skillLevel: 0)
            pilot.skills.setAll(to: 5)
            pilot.skills.setLevels([.gunnery: 2, .drones: 3])
        }
        let levels = await engine.evaluate { stats -> [UInt8?] in
            let pilot = stats.pilots[Self.firstPilot]
            let skills = pilot.skills
            return [skills[typeID: .gunnery]?.level,
                    skills[typeID: .drones]?.level,
                    skills[typeID: .navigation]?.level]
        }
        #expect(levels == [2, 3, 5])
    }

    @Test("Skill level is clamped to 0...5")
    func skillLevelClamped() async throws {
        let engine = DogmaEngine()
        try await engine.edit { fit in
            let pilot = try fit.pilots.add(skillLevel: 0)
            pilot.skills.setLevels([.gunnery: 200])
        }
        let level = await engine.evaluate { stats in
            let pilot = stats.pilots[Self.firstPilot]
            return pilot.skills[typeID: .gunnery]?.level
        }
        #expect(level == 5)
    }

    // MARK: - Write/read symmetry

    @Test("ID sets on the write and read sides agree")
    func writeAndReadSidesAgree() async throws {
        let engine = DogmaEngine()
        let written = try await engine.edit { fit -> (pilots: Int, modules: Int, drones: Int, implants: Int) in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: .rifter)
            try hull.modules.add(.sensorBoosterII)
            try hull.modules.add(.damageControlII)
            try hull.drones.add(.hobgoblinII)
            try pilot.implants.add(.limitedOcularFilter)
            return (fit.pilots.count, hull.modules.count, hull.drones.count, pilot.implants.count)
        }
        let read = await engine.evaluate { stats -> (pilots: Int, modules: Int, drones: Int, implants: Int) in
            let pilot = stats.pilots[Self.firstPilot]
            let hull = pilot.hull
            return (stats.pilots.count, hull.modules.count, hull.drones.count, pilot.implants.count)
        }
        #expect(written == read)
        #expect(read.pilots == 1)
        #expect(read.modules == 2)
        #expect(read.drones == 1)
        #expect(read.implants == 1)
    }

    @Test("forEach visits as many elements as count reports")
    func forEachMatchesCount() async throws {
        let engine = DogmaEngine()
        try await engine.edit { fit in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: .rifter)
            try hull.modules.add(.sensorBoosterII)   // med
            try hull.modules.add(.damageControlII)   // low
            try hull.drones.add(.hobgoblinII)
        }
        let (modules, med, drones) = await engine.evaluate { stats -> (Int, Int, Int) in
            let pilot = stats.pilots[Self.firstPilot]
            let hull = pilot.hull
            var modules = 0, med = 0, drones = 0
            hull.modules.forEach { _ in modules += 1 }
            hull.modules.forEach(in: .med) { _ in med += 1 }
            hull.drones.forEach { _ in drones += 1 }
            return (modules, med, drones)
        }
        #expect(modules == 2)
        #expect(med == 1)
        #expect(drones == 1)
    }
}
