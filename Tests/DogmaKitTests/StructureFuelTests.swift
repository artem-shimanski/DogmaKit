//
//  StructureFuelTests.swift
//  DogmaKit
//
//  Service module fuel on structures, including the hull's fuel role bonus.
//

import Testing
@testable import DogmaKit

@Suite("Structure fuel", .setupDebugNames)
struct StructureFuelTests {

    private static let firstHull = PilotID(1).hull

    private func makeFit(hull hullType: TypeID,
                         modules: [TypeID],
                         state: Entity.Module.State? = nil) async throws -> DogmaEngine {
        let engine = DogmaEngine()
        try await engine.edit { fit in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: hullType)
            for typeID in modules {
                let module = try hull.modules.add(typeID)
                if let state {
                    module.state = state
                }
            }
        }
        return engine
    }

    @Test("Raitaru role bonus cuts Standup Manufacturing Plant I fuel by 25%")
    func raitaruManufacturingPlant() async throws {
        // SDE: 12 blocks/h and 864 to online; Raitaru serviceModuleFuelBonus -25%.
        let engine = try await makeFit(hull: .raitaru, modules: [.standupManufacturingPlantI])
        let (perHour, toOnline, modulePerHour, moduleToOnline) = await engine.evaluate { stats -> (Double, Double, Double, Double) in
            let hull = stats[Self.firstHull]
            let id = Array(hull.modules.ids(in: .service))[0]
            let module = hull.modules[id]
            return (hull.fuelPerHour, hull.fuelToOnline, module.serviceFuelPerHour, module.serviceFuelToOnline)
        }
        #expect(abs(perHour - 9) < 1e-9)
        #expect(abs(toOnline - 648) < 1e-9)
        #expect(abs(modulePerHour - 9) < 1e-9)
        #expect(abs(moduleToOnline - 648) < 1e-9)
    }

    @Test("Fuel sums over service modules; the role bonus covers only its own group")
    func severalModules() async throws {
        let engine = try await makeFit(hull: .raitaru,
                                       modules: [.standupManufacturingPlantI, .standupReprocessingFacilityI])
        let (perHour, toOnline) = await engine.evaluate { stats -> (Double, Double) in
            let hull = stats[Self.firstHull]
            return (hull.fuelPerHour, hull.fuelToOnline)
        }
        // The Raitaru bonus targets engineering service modules only:
        // 12 · 0.75 + 10 and 864 · 0.75 + 720.
        #expect(abs(perHour - 19) < 1e-9)
        #expect(abs(toOnline - 1368) < 1e-9)
    }

    @Test("An offline service module burns no fuel")
    func offlineModuleDoesNotCount() async throws {
        let engine = try await makeFit(hull: .raitaru, modules: [.standupManufacturingPlantI], state: .offline)
        let (perHour, toOnline, modulePerHour) = await engine.evaluate { stats -> (Double, Double, Double) in
            let hull = stats[Self.firstHull]
            let id = Array(hull.modules.ids(in: .service))[0]
            return (hull.fuelPerHour, hull.fuelToOnline, hull.modules[id].serviceFuelPerHour)
        }
        #expect(perHour == 0)
        #expect(toOnline == 0)
        #expect(abs(modulePerHour - 9) < 1e-9)
    }
}
