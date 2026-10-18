//
//  ChargeRemovalTests.swift
//  DogmaKit
//
//  Removing a charge must not break the slot's module list: a charge is not in the
//  allocator list, so remove(_:) must not touch activeHead/activeTail/freeHead.
//

import Foundation
import Testing
@testable import DogmaKit

@Suite("Charge removal", .setupDebugNames)
struct ChargeRemovalTests {

    @Test("Removing a charge keeps both modules; a new module gets a regular ID")
    func removingChargeKeepsSiblingModules() async throws {
        let engine = DogmaEngine()
        let r = try await engine.edit { fit -> (ModuleID, ModuleID, ModuleID, [ModuleID], Bool, Bool, Bool) in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: .rifter)
            let a = try hull.modules.add(.mediumAncillaryShieldBooster)
            let b = try hull.modules.add(.mediumAncillaryShieldBooster)
            try a.setCharge(.capBooster50)
            try b.setCharge(.capBooster50)
            let (aID, bID) = (a.id, b.id)
            hull.modules[aID].charge?.remove()
            let c = try hull.modules.add(.mediumAncillaryShieldBooster)
            let cID = c.id
            return (aID, bID, cID, Array(hull.modules.allIDs),
                    hull.modules[aID].charge != nil, hull.modules[bID].charge != nil, hull.modules[cID].charge != nil)
        }
        #expect(Set(r.3) == Set([r.0, r.1, r.2]))
        #expect(!r.4)
        #expect(r.5)
        #expect(!r.6)
        #expect(!r.2.rawValue.isCharge)
    }

    @Test("Removing a module with a charge leaves its neighbour alone")
    func removingModuleWithChargeKeepsSibling() async throws {
        let engine = DogmaEngine()
        let r = try await engine.edit { fit -> (ModuleID, [ModuleID], Bool) in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: .rifter)
            let a = try hull.modules.add(.mediumAncillaryShieldBooster)
            let b = try hull.modules.add(.mediumAncillaryShieldBooster)
            try a.setCharge(.capBooster50)
            try b.setCharge(.capBooster50)
            let (aID, bID) = (a.id, b.id)
            hull.modules[aID].remove()
            return (bID, Array(hull.modules.allIDs), hull.modules[bID].charge != nil)
        }
        #expect(r.1 == [r.0])
        #expect(r.2)
    }
}
