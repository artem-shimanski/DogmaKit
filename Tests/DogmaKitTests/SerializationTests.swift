//
//  SerializationTests.swift
//  DogmaKit
//
//  Native fit exchange format (`FitDocument`).
//  Main invariant: export -> import -> export yields the same document and the
//  same stats; defaults must be omitted, not lost.
//

import Foundation
import Testing
@testable import DogmaKit

@Suite("Serialization", .setupDebugNames)
struct SerializationTests {

    private static let first = PilotID(1).hull
    private static let second = PilotID(2).hull

    /// A fit exercising every facet of the format: two pilots, states, charges, a socket gap,
    /// a mutation with a roll, drones, implants, environment and a cross target.
    private func makeReferenceEngine() async throws -> DogmaEngine {
        let engine = DogmaEngine()
        try await engine.edit { fit in
            try fit.environment.add(.class3WolfRayetEffects)

            let main = try fit.pilots.add(skillLevel: 5)
            main.skills[typeID: .gunnery]?.level = 3
            try main.implants.add(.limitedOcularFilter)
            let hull = main.hull
            try hull.set(typeID: .rupture)

            let gun = try hull.modules.add(._425mmAutoCannonII)
            try gun.setCharge(.fusionM)
            gun.state = .overloaded

            let second = try hull.modules.add(._425mmAutoCannonII)
            // Socket gap: socket 1 stays empty, which matters for overheating.
            second.socket = 2

            let webID = try hull.modules.add(.stasisWebifierII).id

            let mwd = try hull.modules.add(._50MNMicrowarpdriveI,
                                           mutaplasmid: .unstable50MNMicrowarpdriveMutaplasmid)
            try mwd.setRoll(multiplier: 0.9, for: .cpu)

            let drone = try hull.drones.add(.hobgoblinII, count: 3)
            drone.isActive = true

            let wing = try fit.pilots.add(skillLevel: 4)
            try wing.hull.set(typeID: .rifter)

            // The target is set last: it refers to a hull that did not exist before.
            let web = fit[webID]
            web.target = Self.second
        }
        return engine
    }

    // MARK: - Round-trip

    @Test("Export, import, export gives the same JSON")
    func roundTripIsStable() async throws {
        let engine = try await makeReferenceEngine()
        let first = await engine.export()

        let restored = DogmaEngine()
        let warnings = try await restored.load(first, strict: true)
        let second = await restored.export()

        let firstJSON = try first.jsonData()
        let secondJSON = try second.jsonData()
        #expect(warnings.isEmpty)
        #expect(first == second)
        #expect(firstJSON == secondJSON)
    }

    @Test("Round-trip preserves stats")
    func roundTripPreservesStats() async throws {
        let engine = try await makeReferenceEngine()
        let document = try await engine.export().jsonData()

        let restored = DogmaEngine()
        try await restored.load(FitDocument(jsonData: document), strict: true)

        func snapshot(_ engine: DogmaEngine) async -> [Double] {
            await engine.evaluate { stats in
                let hull = stats[Self.first]
                let dps = hull.dps()
                return [dps.em + dps.thermal + dps.kinetic + dps.explosive,
                        hull.attributes[.armorHP] ?? 0,
                        hull.navigation.maxVelocity,
                        hull.capacitor().delta]
            }
        }
        let before = await snapshot(engine)
        let after = await snapshot(restored)
        #expect(before == after)
    }

    @Test("Round-trip preserves cross targets")
    func roundTripPreservesTargets() async throws {
        let engine = try await makeReferenceEngine()
        let document = await engine.export()
        let restored = DogmaEngine()
        try await restored.load(document, strict: true)

        // FitStats.Module has no target, so read the model directly.
        let targets = await restored.evaluate { stats -> [EntityID] in
            let entities = stats.session.pointee.entities
            var result: [EntityID] = []
            let hull = stats[Self.first]
            for id in hull.modules.allIDs {
                guard let target = entities[id.rawValue]?.kind.module?.target,
                      target != .invalid else { continue }
                result.append(target)
            }
            return result
        }
        #expect(targets == [Self.second.rawValue])
    }

    // MARK: - Defaults

    @Test("Default values are not written to the document")
    func defaultsAreOmitted() async throws {
        let engine = DogmaEngine()
        try await engine.edit { fit in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: .rifter)
            try hull.modules.add(._200mmAutoCannonII)
            try hull.drones.add(.hobgoblinII)
        }
        let document = await engine.export()
        let module = try #require(document.pilots.first?.ship?.modules.first)
        let drone = try #require(document.pilots.first?.ship?.drones.first)

        #expect(module.socket == nil)          // first in the rack
        #expect(module.state == nil)           // .active is the default for activatable modules
        #expect(module.charge == nil)
        #expect(module.target == nil)
        #expect(drone.count == 5)              // full flight, written explicitly
        #expect(drone.active == nil)

        // Skills: "all at V" is one line, not 500.
        let skills = try #require(document.pilots.first?.skills)
        #expect(skills.default == 5)
        #expect(skills.levels.isEmpty)
    }

    @Test("A full fighter squadron is written with the squadron size")
    func fighterCountIsExplicit() async throws {
        let engine = DogmaEngine()
        let size = try await engine.edit { fit -> UInt8 in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: .thanatos)
            return try hull.drones.add(.einherjiI).squadronSize
        }
        let document = await engine.export()
        let drone = try #require(document.pilots.first?.ship?.drones.first)
        #expect(size >= 1)
        #expect(drone.count == size)
    }

    @Test("A rack gap is written explicitly")
    func socketGapIsExplicit() async throws {
        let engine = try await makeReferenceEngine()
        let document = await engine.export()
        let guns = try #require(document.pilots.first?.ship?.modules)
            .filter { $0.type == ._425mmAutoCannonII }

        #expect(guns.count == 2)
        #expect(guns[0].socket == nil)
        #expect(guns[1].socket == 2)
    }

    @Test("Skill deviations are written as exceptions and restored")
    func skillExceptionsRoundTrip() async throws {
        let engine = try await makeReferenceEngine()
        let document = await engine.export()
        let skills = try #require(document.pilots.first?.skills)

        #expect(skills.default == 5)
        #expect(skills.levels.count == 1)
        #expect(skills.levels.first?.type == .gunnery)
        #expect(skills.levels.first?.level == 3)

        let restored = DogmaEngine()
        try await restored.load(document, strict: true)
        let level = await restored.evaluate { stats in
            let pilot = stats.pilots[PilotID(1)]
            return pilot.skills[typeID: .gunnery]?.level
        }
        #expect(level == 3)
    }

    // MARK: - Format

    @Test("A bare TypeID and a named object read the same")
    func itemAcceptsBothForms() throws {
        let bare = try JSONDecoder().decode(FitDocument.Item.self, from: Data("13219".utf8))
        let named = try JSONDecoder().decode(FitDocument.Item.self,
                                             from: Data(#"{"type": 13219, "_name": "x"}"#.utf8))
        #expect(bare.type == named.type)
        #expect(bare.name == nil)
        #expect(named.name == "x")

        // Without a name it is encoded as a number to keep implant lists compact.
        let encoded = String(decoding: try JSONEncoder().encode(bare), as: UTF8.self)
        #expect(encoded == "13219")
    }

    @Test("Names are an export option and ignored on import")
    func namesAreInformationalOnly() async throws {
        let engine = try await makeReferenceEngine()
        let named = await engine.export(name: "reference") { typeID in "type-\(typeID.rawValue)" }
        #expect(named.name == "reference")
        #expect(named.pilots.first?.ship?.name == "type-\(TypeID.rupture.rawValue)")

        // Import ignores names, so re-exporting WITHOUT names matches a plain export.
        let restored = DogmaEngine()
        try await restored.load(named, strict: true)
        let plain = await engine.export()
        let reexported = await restored.export()
        #expect(plain == reexported)
    }

    @Test("Unknown type: lenient mode warns, strict mode throws")
    func unknownTypeDegradesGracefully() async throws {
        var document = FitDocument()
        document.pilots = [.init(skills: .init(default: 5),
                                 ship: .init(type: .rifter, modules: [.init(type: TypeID(rawValue: 999_999))]))]

        let soft = DogmaEngine()
        let warnings = try await soft.load(document)
        #expect(warnings.count == 1)

        let hullHasNoModules = await soft.evaluate { stats in
            let hull = stats[Self.first]
            return hull.modules.count == 0
        }
        #expect(hullHasNoModules)

        let strict = DogmaEngine()
        await #expect(throws: FitDocument.Warning.self) {
            try await strict.load(document, strict: true)
        }
    }

    @Test("A mutation is restored together with its rolls")
    func mutationRoundTrips() async throws {
        let engine = try await makeReferenceEngine()
        let document = await engine.export()
        let mutated = try #require(document.pilots.first?.ship?.modules.first { $0.mutation != nil })

        #expect(mutated.type == ._50MNMicrowarpdriveI)
        #expect(mutated.mutation?.mutaplasmid.type == .unstable50MNMicrowarpdriveMutaplasmid)
        // Only the changed roll is written; the rest stay at base values.
        #expect(mutated.mutation?.rolls.count == 1)
        #expect(mutated.mutation?.rolls.first?.attribute == .cpu)

        let restored = DogmaEngine()
        try await restored.load(document, strict: true)
        let reexported = await restored.export()
        #expect(reexported == document)
    }

    @Test("Environment survives a round-trip")
    func environmentRoundTrips() async throws {
        let engine = try await makeReferenceEngine()
        let document = await engine.export()
        #expect(document.environment.map(\.type) == [.class3WolfRayetEffects])

        let restored = DogmaEngine()
        try await restored.load(document, strict: true)
        let count = await restored.evaluate { $0.environment.count }
        #expect(count == 1)
    }

    // MARK: - Single fleet pilot

    /// Two pilots with mutual targets and an environment; the second's target is the first.
    private func makeFleetEngine() async throws -> DogmaEngine {
        let engine = try await makeReferenceEngine()
        try await engine.edit { fit in
            let wing = fit[Self.second.pilot]
            let hull = wing.hull
            let web = try hull.modules.add(.stasisWebifierII)
            web.target = Self.first
        }
        return engine
    }

    @Test("Single-pilot export: no targets or environment, round-trip is stable")
    func singlePilotExport() async throws {
        let engine = try await makeFleetEngine()
        let full = await engine.export()
        #expect(full.pilots.count == 2)
        #expect(full.pilots[0].ship?.modules.contains { $0.target != nil } == true)
        #expect(full.pilots[1].ship?.modules.contains { $0.target != nil } == true)
        #expect(full.environment.count == 1)

        let single = await engine.export(pilot: Self.second.pilot)
        #expect(single.pilots.count == 1)
        #expect(single.pilots[0] == full.pilots[1].withoutTargets)
        #expect(single.environment.isEmpty)
        let hasTarget = single.pilots[0].ship?.modules.contains { $0.target != nil } ?? false
        #expect(!hasTarget)

        let restored = DogmaEngine()
        try await restored.load(single, strict: true)
        let again = await restored.export(pilot: Self.first.pilot)
        #expect(again == single)
        #expect(await restored.export() == single)
    }

    @Test("Single-pilot export: a self-target is omitted too")
    func singlePilotDropsSelfTarget() async throws {
        let engine = try await makeFleetEngine()
        let single = await engine.export(pilot: Self.first.pilot)
        let targets = single.pilots[0].ship?.modules.compactMap(\.target) ?? []
        #expect(targets.isEmpty)
    }

    @Test("An unknown pilot gives a document without pilots")
    func singlePilotUnknown() async throws {
        let engine = try await makeFleetEngine()
        let single = await engine.export(pilot: PilotID(5))
        #expect(single.pilots.isEmpty)
        #expect(single.environment.isEmpty)
    }
}

private extension FitDocument.Pilot {
    /// A pilot with `target` cleared, the reference for comparing with a single-pilot export.
    var withoutTargets: FitDocument.Pilot {
        var copy = self
        if var ship = copy.ship {
            for i in ship.modules.indices { ship.modules[i].target = nil }
            for i in ship.drones.indices { ship.drones[i].target = nil }
            copy.ship = ship
        }
        return copy
    }
}
