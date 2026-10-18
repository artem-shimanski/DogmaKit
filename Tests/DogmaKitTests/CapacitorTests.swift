//
//  CapacitorTests.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 28.07.2026.
//

import Testing
@testable import DogmaKit

@Suite("Capacitor", .setupDebugNames)
struct CapacitorTests {
    
    @Test("Modules increase capacitor drain")
    func capacitorDrain() async throws {
        let engine = DogmaEngine()
        let hullA = PilotID(1).hull
        
        try await engine.edit { fit in
            let pilotA = try fit.pilots.add(skillLevel: 5)
            let hullA = pilotA.hull
            try hullA.set(typeID: .dominix)
            try hullA.modules.add(.mediumArmorRepairerII)
        }
        
        let cap0 = await engine.evaluate { stats in
            stats[hullA].capacitor()
        }
        
        try await engine.edit { fit in
            let hull = fit[hullA]
            try hull.modules.add(.mediumArmorRepairerII)
        }
        
        let cap1 = await engine.evaluate { stats in
            stats[hullA].capacitor()
        }
        
        #expect(abs(cap1.averageDrain / cap0.averageDrain - 2) < 1e-6)
        #expect(cap0.delta > cap1.delta)
        #expect(abs(cap0.rechargeTime - cap1.rechargeTime) < 1e-6)
        #expect(cap0.lastsFor.isInfinite)
        #expect((cap0.stableLevel ?? 0) > (cap1.stableLevel ?? 0))
    }
    
    @Test("A cap booster speeds up capacitor recharge")
    func capBooster() async throws {
        let engine = DogmaEngine()
        let hullA = PilotID(1).hull
        
        try await engine.edit { fit in
            let pilotA = try fit.pilots.add(skillLevel: 5)
            let hullA = pilotA.hull
            try hullA.set(typeID: .dominix)
            try hullA.modules.add(._500MNMicrowarpdriveII)
        }

        let cap0 = await engine.evaluate { stats in
            stats[hullA].capacitor()
        }

        try await engine.edit { fit in
            let hull = fit[hullA]
            let module = try hull.modules.add(.heavyCapacitorBoosterII)
            try module.setCharge(.capBooster100)
        }

        let cap1 = await engine.evaluate { stats in
            stats[hullA].capacitor()
        }
        #expect(cap0.delta < 0)
        #expect(cap0.stableLevel == nil)
        #expect(cap0.lastsFor.isFinite && cap0.lastsFor > 0)
        
        #expect(cap1.delta > 0)
        #expect((cap1.stableLevel ?? 0) > 0.25)
    }
    
    
    @Test("Remote capacitor transfer, neutralizing and draining")
    func remoteEnergyDrainers() async throws {
        let engine = DogmaEngine()
        let hullAID = PilotID(1).hull
        let hullBID = PilotID(2).hull
        
        func stats() async -> (src: CapacitorSimulator.Result, dst: CapacitorSimulator.Result) {
            await engine.evaluate { stats in
                (stats[hullAID].capacitor(),
                 stats[hullBID].capacitor())
            }
        }
        
        func add(_ typeID: TypeID) async throws {
            try await engine.edit { fit in
                let hullA = fit[hullAID]
                let module = try hullA.modules.add(typeID)
                module.target = hullBID
            }
        }

        
        try await engine.edit { fit in
            let pilotA = try fit.pilots.add(skillLevel: 5)
            let pilotB = try fit.pilots.add(skillLevel: 5)
            
            let hullA = pilotA.hull
            let hullB = pilotB.hull
            
            try hullA.set(typeID: .dominix)
            try hullB.set(typeID: .dominix)
        }
        
        let base = await stats()
        
        try await add(.heavyEnergyNeutralizerI)
        let neut = await stats()

        try await add(.heavyEnergyNosferatuI)
        let nosf = await stats()

        try await add(.largeRemoteCapacitorTransmitterI)
        let rct = await stats()

        #expect(neut.src.averageDrain > base.src.averageDrain, "heavyEnergyNeutralizerI drains the owner capacitor")
        #expect(neut.dst.averageDrain > base.dst.averageDrain, "heavyEnergyNeutralizerI drains the target capacitor")
        #expect(abs(neut.src.averageRecharge - base.src.averageRecharge) < 1e-6, "heavyEnergyNeutralizerI does not regenerate capacitor")
        #expect(abs(nosf.src.averageDrain - neut.src.averageDrain) < 1e-06, "heavyEnergyNosferatuI does not drain the owner capacitor")
        #expect(nosf.src.averageRecharge > neut.src.averageRecharge, "heavyEnergyNosferatuI regenerates the owner capacitor")
        #expect(nosf.dst.averageDrain > neut.dst.averageDrain, "heavyEnergyNosferatuI drains the target capacitor")
        #expect(rct.src.averageDrain > nosf.src.averageDrain, "largeRemoteCapacitorTransmitterI drains the owner capacitor")
        #expect(rct.dst.averageRecharge > neut.dst.averageRecharge, "largeRemoteCapacitorTransmitterI regenerates the target capacitor")
    }
}
