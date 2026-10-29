//
//  FitStatsFieldsTests.swift
//  DogmaKit
//
//  Read fields derived from single attributes: charge load, per-drone volume and bandwidth,
//  bays and squadron slots, unfiltered projected capacitor, subsystem slot modifiers.
//  Expectations are derived from the calculated attributes, and every field is checked on
//  the snapshot as well.
//

import Testing
@testable import DogmaKit

@Suite("FitStats fields", .setupDebugNames)
struct FitStatsFieldsTests {

    private static let hullA = PilotID(1).hull

    @Test("Charge count fills the module's capacity, rounded down")
    func chargeCount() async throws {
        let engine = DogmaEngine()
        let (turretID, boosterID, emptyID) = try await engine.edit { fit in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: .dominix)
            let turret = try hull.modules.add(._425mmAutoCannonII)
            try turret.setCharge(.fusionM)
            let booster = try hull.modules.add(.heavyCapacitorBoosterII)
            try booster.setCharge(.capBooster800)
            let empty = try hull.modules.add(._425mmAutoCannonII)
            return (turret.id, booster.id, empty.id)
        }

        let reads = await engine.evaluate { stats in
            [turretID, boosterID, emptyID].map { id in
                let module = stats[id]
                return (count: module.chargeCount,
                        capacity: module.chargeCapacity,
                        attributeCapacity: module.attributes[.capacity] ?? 0,
                        volume: module.charge?.volume,
                        attributeVolume: module.charge?.attributes[.volume],
                        snapshot: module.snapshot())
            }
        }

        for read in reads.prefix(2) {
            let volume = try #require(read.volume)
            #expect(volume == read.attributeVolume)
            #expect(volume > 0)
            #expect(read.capacity == read.attributeCapacity)
            #expect(read.count == Int((read.capacity / volume).rounded(.down)))
            #expect(read.count >= 1)
            #expect(read.snapshot.chargeCount == read.count)
            #expect(read.snapshot.chargeCapacity == read.capacity)
            #expect(read.snapshot.charge?.volume == volume)
        }
        #expect(reads[2].count == 0)
        #expect(reads[2].volume == nil)
        #expect(reads[2].snapshot.chargeCount == 0)
        #expect(reads[2].snapshot.charge == nil)
    }

    @Test("Per-drone volume and bandwidth; bays multiply them by the stack")
    func droneVolumeAndBandwidth() async throws {
        let engine = DogmaEngine()
        let droneID = try await engine.edit { fit in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: .dominix)
            let drones = try hull.drones.add(.hammerheadII, count: 3)
            drones.isActive = true
            return drones.id
        }

        let (volume, bandwidth, velocity, attributes, bay, used, snapshot) = await engine.evaluate { stats in
            let drone = stats[droneID]
            let hull = stats[Self.hullA]
            return (drone.volume, drone.bandwidthUsed, drone.maxVelocity,
                    [drone.attributes[.volume], drone.attributes[.droneBandwidthUsed],
                     drone.attributes[.maxVelocity]],
                    hull.droneBay.used, hull.droneBandwidth.used, drone.snapshot())
        }

        #expect([volume, bandwidth, velocity] == attributes)
        #expect(volume > 0 && bandwidth > 0 && velocity > 0)
        #expect(bay == volume * 3)
        #expect(used == bandwidth * 3)
        #expect(snapshot.volume == volume)
        #expect(snapshot.bandwidthUsed == bandwidth)
        #expect(snapshot.maxVelocity == velocity)
    }

    @Test("Fighters use tubes and squadron slots, not drones in space")
    func fighterTubesAndSquadrons() async throws {
        let engine = DogmaEngine()
        try await engine.edit { fit in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: .thanatos)
            let launched = try hull.drones.add(.einherjiI)
            launched.isActive = true
            try hull.drones.add(.einherjiI)
            let support = try hull.drones.add(.cenobiteI)
            support.isActive = true
            let drones = try hull.drones.add(.hammerheadII, count: 2)
            drones.isActive = true
        }

        let (inSpace, tubes, tubesTotal, light, lightTotal, support, supportTotal, squadrons, snapshot) =
            await engine.evaluate { stats in
                let hull = stats[Self.hullA]
                return (hull.dronesInSpace,
                        hull.fighterTubes, hull.attributes[.fighterTubes] ?? 0,
                        hull.capacity(of: .light), hull.attributes[.fighterLightSlots] ?? 0,
                        hull.capacity(of: .support), hull.attributes[.fighterSupportSlots] ?? 0,
                        hull.squadrons, hull.snapshot())
            }

        #expect(inSpace.used == 2)
        #expect(tubes == SlotCapacity(used: 2, total: Int(tubesTotal)))
        #expect(tubes.total > 0)
        #expect(light == SlotCapacity(used: 2, total: Int(lightTotal)))
        #expect(light.total > 0)
        #expect(support == SlotCapacity(used: 1, total: Int(supportTotal)))
        #expect(Set(squadrons.keys) == Set(Entity.Drone.Squadron.allCases.filter { $0 != .none }))
        #expect(squadrons[.heavy]?.used == 0)

        #expect(snapshot.dronesInSpace == inSpace)
        #expect(snapshot.fighterTubes == tubes)
        #expect(snapshot.squadrons == squadrons)
        #expect(snapshot.capacity(of: .light) == light)
        #expect(snapshot.capacity(of: .none) == SlotCapacity(used: 0, total: 0))
    }

    @Test("Cargo capacity is the hull's capacity attribute")
    func cargoCapacity() async throws {
        let engine = DogmaEngine()
        try await engine.edit { fit in
            let pilot = try fit.pilots.add(skillLevel: 5)
            try pilot.hull.set(typeID: .dominix)
        }
        let (cargo, attribute, snapshot) = await engine.evaluate { stats in
            let hull = stats[Self.hullA]
            return (hull.cargoCapacity, hull.attributes[.capacity], hull.snapshot())
        }
        #expect(cargo == attribute)
        #expect(cargo > 0)
        #expect(snapshot.cargoCapacity == cargo)
    }

    @Test("Unfiltered projected capacitor of modules and drones")
    func projectedCapacitor() async throws {
        let engine = DogmaEngine()
        let (neutID, idleID, transmitterID, droneID) = try await engine.edit { fit in
            let pilotA = try fit.pilots.add(skillLevel: 5)
            let hullA = pilotA.hull
            try hullA.set(typeID: .dominix)

            let pilotB = try fit.pilots.add(skillLevel: 5)
            let hullB = pilotB.hull
            try hullB.set(typeID: .dominix)
            let neut = try hullB.modules.add(.heavyEnergyNeutralizerII)
            neut.state = .active
            neut.target = Self.hullA
            let idle = try hullB.modules.add(.heavyEnergyNeutralizerII)
            idle.state = .online
            let transmitter = try hullB.modules.add(.largeRemoteCapacitorTransmitterI)
            transmitter.state = .active
            transmitter.target = Self.hullA
            let drones = try hullB.drones.add(.acolyteEV300, count: 2)
            drones.isActive = true
            drones.target = Self.hullA
            return (neut.id, idle.id, transmitter.id, drones.id)
        }

        let reads = await engine.evaluate { stats in
            (neut: (stats[neutID].projectedCapacitorNode(),
                    stats[neutID].projectedCapacitorNode(disallowOffensive: false, disallowAssistance: false),
                    stats[neutID].snapshot().projectedCapacitorNode),
             idle: stats[idleID].snapshot().projectedCapacitorNode,
             transmitter: stats[transmitterID].projectedCapacitorNode(),
             drone: (stats[droneID].projectedCapacitorNode(),
                     stats[droneID].projectedCapacitorNode(disallowOffensive: false, disallowAssistance: false),
                     stats[droneID].snapshot().projectedCapacitorNode,
                     stats[droneID].attributes[.energyNeutralizerAmount] ?? 0,
                     stats[droneID].attributes[.energyNeutralizerDuration] ?? 0),
             incoming: stats[Self.hullA].capacitorSimulator().nodes)
        }

        let neut = try #require(reads.neut.0)
        #expect(neut.drain > 0 && neut.recharge == 0)
        #expect(reads.neut.1 == neut)
        #expect(reads.neut.2 == neut)
        #expect(reads.idle == nil)

        let transmitter = try #require(reads.transmitter)
        #expect(transmitter.recharge > 0 && transmitter.drain == 0)

        let drone = try #require(reads.drone.0)
        // Neutralizer drones cycle on `energyNeutralizerDuration`; the drain is for the stack.
        #expect(drone.cycleTime == reads.drone.4 / 1000)
        #expect(drone.drain == reads.drone.3 * 2)
        #expect(drone.averageDrain > 0)
        #expect(reads.drone.1 == drone)
        #expect(reads.drone.2 == drone)

        #expect(Set(reads.incoming.map(\.drain)) == Set([neut, transmitter, drone].map(\.drain)))
    }

    @Test("Subsystem slot and hardpoint modifiers")
    func subsystemModifiers() async throws {
        let engine = DogmaEngine()
        let (subsystemIDs, plainID) = try await engine.edit { fit in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: .tengu)
            let subsystems = try [
                TypeID.tenguCoreAugmentedGravitonReactor,
                .tenguDefensiveSupplementalScreening,
                .tenguOffensiveAcceleratedEjectionBay,
                .tenguPropulsionChassisOptimization,
            ].map { try hull.modules.add($0).id }
            let plain = try hull.modules.add(.heavyMissileLauncherII)
            return (subsystems, plain.id)
        }

        let (reads, plain) = await engine.evaluate { stats in
            (subsystemIDs.map { id in
                let module = stats[id]
                let attributes = module.attributes
                func value(_ id: AttributeID) -> Int { Int(attributes[id] ?? 0) }
                return (slots: module.slotModifiers,
                        hardpoints: module.hardpointModifiers,
                        expectedSlots: [Entity.Module.Slot.hi: value(.hiSlotModifier),
                                        .med: value(.medSlotModifier),
                                        .low: value(.lowSlotModifier)].filter { $0.value != 0 },
                        expectedHardpoints: [Entity.Module.Hardpoint.turret: value(.turretHardPointModifier),
                                             .launcher: value(.launcherHardPointModifier)].filter { $0.value != 0 },
                        snapshot: module.snapshot())
            }, stats[plainID].snapshot())
        }

        for read in reads {
            #expect(read.slots == read.expectedSlots)
            #expect(read.hardpoints == read.expectedHardpoints)
            #expect(read.snapshot.slotModifiers == read.slots)
            #expect(read.snapshot.hardpointModifiers == read.hardpoints)
        }
        #expect(reads.contains { !$0.slots.isEmpty })
        #expect(reads.contains { $0.hardpoints[.launcher, default: 0] > 0 })
        #expect(plain.slotModifiers.isEmpty)
        #expect(plain.hardpointModifiers.isEmpty)
    }
}
