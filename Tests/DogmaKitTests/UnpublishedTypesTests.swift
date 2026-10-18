//
//  UnpublishedTypesTests.swift
//  DogmaKit
//
//  The importer takes every type the engine can compute (one with a dogma record), not only
//  published ones. `published` in the SDE does not mean "exists in game": Civilian guns and the
//  Civilian Data Analyzer/Salvager are unpublished but appear in fits. Such types must fit and compute.
//

import Testing
@testable import DogmaKit

@Suite("Unpublished types", .setupDebugNames)
struct UnpublishedTypesTests {

    private static let firstHull = PilotID(1).hull

    @Test("Unpublished Civilian modules fit and compute")
    func civilianModules() async throws {
        let engine = DogmaEngine()
        try await engine.edit { fit in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: .impairor)
            let gun = try hull.modules.add(.civilianGatlingPulseLaser)
            // No ammo needed: Civilian guns have no `chargeGroup`; the damage is on the module itself.
            gun.state = .active
            _ = try hull.modules.add(.civilianDataAnalyzer)
            _ = try hull.modules.add(.civilianSalvager)
        }

        let (count, volley) = await engine.evaluate { stats -> (Int, Double) in
            let hull = stats[Self.firstHull]
            let gunID = hull.modules.ids(in: .hi).first { hull.modules[$0].typeID == .civilianGatlingPulseLaser }!
            let damage = hull.modules[gunID].volleyDamage
            return (hull.modules.count, damage.em + damage.thermal + damage.kinetic + damage.explosive)
        }
        #expect(count == 3)
        #expect(volley > 0)
    }
}
