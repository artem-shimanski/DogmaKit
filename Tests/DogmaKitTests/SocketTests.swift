//
//  SocketTests.swift
//  DogmaKit
//
//  Module position in the rack. It matters for overheating: damage to neighbours decays as
//  `heatAttenuation ^ |delta socket|`.
//

import Testing
@testable import DogmaKit

@Suite("Module socket in the rack", .setupDebugNames)
struct SocketTests {

    private static let firstHull = PilotID(1).hull

    private static func rifter() async throws -> DogmaEngine {
        let engine = DogmaEngine()
        try await engine.edit { fit in
            let pilot = try fit.pilots.add(skillLevel: 5)
            try pilot.hull.set(typeID: .rifter)
        }
        return engine
    }

    /// Rack sockets in module enumeration order.
    private static func sockets(_ engine: DogmaEngine, _ slot: Entity.Module.Slot) async -> [Int] {
        await engine.evaluate { stats in
            var result: [Int] = []
            let hull = stats[Self.firstHull]
            hull.modules.forEach(in: slot) { result.append($0.socket) }
            return result
        }
    }

    @Test("Sequential adds number the sockets in order")
    func sequentialAdd() async throws {
        let engine = try await Self.rifter()
        try await engine.edit { fit in
            let hull = fit[Self.firstHull]
            try hull.modules.add(._200mmAutoCannonII)
            try hull.modules.add(._200mmAutoCannonII)
            try hull.modules.add(._200mmAutoCannonII)
        }
        #expect(await Self.sockets(engine, .hi) == [0, 1, 2])
    }

    @Test("Racks are numbered independently")
    func racksAreIndependent() async throws {
        let engine = try await Self.rifter()
        try await engine.edit { fit in
            let hull = fit[Self.firstHull]
            try hull.modules.add(._200mmAutoCannonII)
            try hull.modules.add(.warpScramblerII)
            try hull.modules.add(._5MNMicrowarpdriveII)
            try hull.modules.add(.smallArmorRepairerII)
        }
        #expect(await Self.sockets(engine, .hi) == [0])
        #expect(await Self.sockets(engine, .med) == [0, 1])
        #expect(await Self.sockets(engine, .low) == [0])
    }

    @Test("Removal leaves a hole and the next module fills it")
    func removeLeavesHole() async throws {
        let engine = try await Self.rifter()
        let middle = try await engine.edit { fit -> ModuleID in
            let hull = fit[Self.firstHull]
            try hull.modules.add(._200mmAutoCannonII)
            let middle = try hull.modules.add(._200mmAutoCannonII).id
            try hull.modules.add(._200mmAutoCannonII)
            return middle
        }
        #expect(await Self.sockets(engine, .hi) == [0, 1, 2])

        try await engine.edit { fit in
            fit[middle].remove()
        }
        // The rest do not shift: socket 1 stays empty.
        #expect(await Self.sockets(engine, .hi) == [0, 2])

        try await engine.edit { fit in
            let hull = fit[Self.firstHull]
            try hull.modules.add(._200mmAutoCannonII)
        }
        // A new module takes the freed index, not the rack tail. The enumeration
        // order then no longer matches the socket order.
        #expect(await Self.sockets(engine, .hi) == [0, 2, 1])
    }

    @Test("Assigning a free socket simply moves the module")
    func moveToFreeSocket() async throws {
        let engine = try await Self.rifter()
        let first = try await engine.edit { fit -> ModuleID in
            let hull = fit[Self.firstHull]
            let first = try hull.modules.add(._200mmAutoCannonII).id
            try hull.modules.add(._200mmAutoCannonII)
            return first
        }

        try await engine.edit { fit in
            fit[first].socket = 5
        }
        #expect(await Self.sockets(engine, .hi) == [5, 1])
    }

    @Test("Assigning an occupied socket swaps the modules")
    func swapSockets() async throws {
        let engine = try await Self.rifter()
        let (first, second) = try await engine.edit { fit -> (ModuleID, ModuleID) in
            let hull = fit[Self.firstHull]
            let first = try hull.modules.add(._200mmAutoCannonII).id
            let second = try hull.modules.add(._200mmAutoCannonII).id
            try hull.modules.add(._200mmAutoCannonII)
            return (first, second)
        }

        try await engine.edit { fit in
            fit[first].socket = 2
        }
        #expect(await Self.sockets(engine, .hi) == [2, 1, 0])

        // A swap cannot create duplicates or lose modules.
        let unique = await engine.evaluate { stats -> Bool in
            let hull = stats[Self.firstHull]
            var seen: Set<Int> = []
            var duplicate = false
            hull.modules.forEach(in: .hi) { if !seen.insert($0.socket).inserted { duplicate = true } }
            return !duplicate && seen.count == 3
        }
        #expect(unique)

        // Assigning the same value is a no-op, not a swap with itself.
        try await engine.edit { fit in
            fit[second].socket = 1
        }
        #expect(await Self.sockets(engine, .hi) == [2, 1, 0])
    }

    @Test("Mutating a module keeps its rack position")
    func mutationKeepsSocket() async throws {
        let engine = try await Self.rifter()
        let mwd = try await engine.edit { fit -> ModuleID in
            let hull = fit[Self.firstHull]
            try hull.modules.add(.warpScramblerII)
            return try hull.modules.add(._50MNMicrowarpdriveI).id
        }
        #expect(await Self.sockets(engine, .med) == [0, 1])

        try await engine.edit { fit in
            try fit[mwd].mutate(with: .unstable50MNMicrowarpdriveMutaplasmid)
        }
        #expect(await Self.sockets(engine, .med) == [0, 1])

        try await engine.edit { fit in
            try fit[mwd].demutate()
        }
        #expect(await Self.sockets(engine, .med) == [0, 1])
    }
}
