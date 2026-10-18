//
//  TacticalDestroyerTests.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 30.07.2026.
//

import Testing
@testable import DogmaKit

@Suite("Tactical destroyers", .setupDebugNames)
struct TacticalDestroyerTests {
    
    @Test("Hecate tactical modes")
    func hecateTacticalModes() async throws {
        let engine = DogmaEngine()
        let hullID = PilotID(1).hull
        
        var tacticalModeID = try await engine.edit { fit -> ModuleID in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: .hecate)
            
            try hull.modules.add(._5MNMicrowarpdriveII)
            try hull.modules.add(.smallArmorRepairerII)
            try hull.modules.add(.smallShieldBoosterII)
            let mode = try hull.modules.add(.hecateDefenseMode)
            
            return mode.id
        }
        
        let (cap0, v0, tank0, res0) = await engine.evaluate { stats in
            let hull = stats[hullID]
            return (hull.capacitor(), hull.navigation.maxVelocity, hull.tank(), hull.resistances)
        }
        
        tacticalModeID = try await engine.edit { [tacticalModeID] fit -> ModuleID in
            let hull = fit[hullID]
            fit[tacticalModeID].remove()
            return try hull.modules.add(.hecatePropulsionMode).id
        }
        
        let (cap1, v1, tank1, res1) = await engine.evaluate { stats in
            let hull = stats[hullID]
            return (hull.capacitor(), hull.navigation.maxVelocity, hull.tank(), hull.resistances)
        }
        
        #expect(cap1.delta > cap0.delta, "hecatePropulsionMode reduces the MWD capacitor use")
        #expect(v1 > v0, "hecatePropulsionMode increases the MWD speed bonus")
        #expect(tank0.armorRepair > tank1.armorRepair, "hecateDefenseMode increases armor repairer effectiveness")
        #expect(abs(tank0.shieldRepair - tank1.shieldRepair) < 1e-6, "hecateDefenseMode does not affect the shield booster")
        #expect(res0.armor.sum() > res1.armor.sum(), "hecateDefenseMode increases armor resistances")
        #expect(res0.hull.sum() > res1.hull.sum(), "hecateDefenseMode increases hull resistances")
        #expect(abs(res0.shield.sum() - res1.shield.sum()) < 1e-6, "hecateDefenseMode does not affect shield resistances")
    }
}
