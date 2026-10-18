//
//  PilotLimitTests.swift
//  DogmaKit
//
//  Pilot limit (`Fit.Pilots.maxCount`) and the `isProjectable` flag of modules and drones.
//

import Testing
@testable import DogmaKit

@Suite("Pilot limit and projectable flag", .setupDebugNames)
struct PilotLimitTests {

    @Test("Seven pilots are added; the eighth throws pilotLimitExceeded and allocates nothing")
    func eighthPilotThrows() async throws {
        #expect(Fit.Pilots.maxCount == 7)
        let engine = DogmaEngine()
        try await engine.edit { fit in
            for _ in 0..<Fit.Pilots.maxCount {
                try fit.pilots.add(skillLevel: 1)
            }
            #expect(fit.pilots.count == 7)
            do {
                try fit.pilots.add(skillLevel: 1)
                Issue.record("expected pilotLimitExceeded")
            } catch {
                guard case DogmaError.pilotLimitExceeded = error else {
                    Issue.record("unexpected error \(error)")
                    return
                }
            }
            #expect(fit.pilots.count == 7)
        }
    }

    @Test("A document with eight pilots fails to load in both strict and soft mode")
    func documentWithEightPilotsFails() async throws {
        var document = FitDocument()
        document.pilots = Array(repeating: .init(skills: .init(default: 0)), count: 8)

        for strict in [true, false] {
            let engine = DogmaEngine()
            do {
                try await engine.load(document, strict: strict)
                Issue.record("load must throw (strict: \(strict))")
            } catch {
                guard case FitDocument.Warning.pilotRejected(_, .pilotLimitExceeded) = error else {
                    Issue.record("unexpected warning \(error)")
                    continue
                }
            }
        }

        document.pilots.removeLast()
        let engine = DogmaEngine()
        try await engine.load(document, strict: true)
    }

    @Test("isProjectable: remote repairer and warp disruptor yes, gun and damage control no")
    func projectableFlag() async throws {
        let engine = DogmaEngine()
        try await engine.edit { fit in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: .dominix)
            try hull.modules.add(.largeRemoteArmorRepairerI)
            try hull.modules.add(.warpDisruptorI)
            try hull.modules.add(.heavyElectronBlasterI)
            try hull.modules.add(.damageControlII)
        }
        let flags = await engine.evaluate { stats -> [TypeID: Bool] in
            var result: [TypeID: Bool] = [:]
            let hull = stats[PilotID(1).hull]
            for id in hull.modules.allIDs {
                result[hull.modules[id].typeID] = hull.modules[id].isProjectable
            }
            return result
        }
        #expect(flags[.largeRemoteArmorRepairerI] == true)
        #expect(flags[.warpDisruptorI] == true)
        #expect(flags[.heavyElectronBlasterI] == false)
        #expect(flags[.damageControlII] == false)

        let fitFlags = try await engine.edit { fit -> [TypeID: Bool] in
            let hull = fit[PilotID(1).hull]
            return Dictionary(uniqueKeysWithValues: hull.modules.allIDs.map { (hull.modules[$0].typeID, hull.modules[$0].isProjectable) })
        }
        #expect(fitFlags == flags)
    }
}
