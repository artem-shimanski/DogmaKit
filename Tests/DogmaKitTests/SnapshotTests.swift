//
//  SnapshotTests.swift
//  DogmaKit
//
//  Snapshots copy `FitStats` values out of the engine. They must match the live read
//  exactly (the math is shared, not duplicated) and stay unchanged after the fit is edited.
//

import Testing
@testable import DogmaKit

@Suite("Snapshots", .setupDebugNames)
struct SnapshotTests {

    private static let hullA = PilotID(1).hull
    private static let pilotC = PilotID(3)

    private static let targets: [Target] = [
        .zero,
        Target(angularVelocity: 0.02, velocity: 150, signature: 400, range: 5_000),
        Target(angularVelocity: 0.08, velocity: 600, signature: 60, range: 25_000),
    ]

    /// Pilot 1: Dominix with guns, launcher, armor repairer, cap booster, an offline turret and
    /// Hammerheads. Pilot 2: Dominix neutralizing pilot 1. Pilot 3: no ship (a capsule).
    private static func engine() async throws -> (DogmaEngine, offlineTurret: ModuleID, repairer: ModuleID) {
        let engine = DogmaEngine()
        let ids = try await engine.edit { fit in
            let pilotA = try fit.pilots.add(skillLevel: 5)
            let hullA = pilotA.hull
            try hullA.set(typeID: .dominix)
            let turret = try hullA.modules.add(._425mmAutoCannonII)
            turret.state = .active
            try turret.setCharge(.fusionM)
            let launcher = try hullA.modules.add(.heavyMissileLauncherII)
            launcher.state = .active
            try launcher.setCharge(.scourgeHeavyMissile)
            let offline = try hullA.modules.add(._425mmAutoCannonII)
            offline.state = .online
            try offline.setCharge(.fusionM)
            let repairer = try hullA.modules.add(.largeArmorRepairerII)
            repairer.state = .active
            let booster = try hullA.modules.add(.heavyCapacitorBoosterII)
            booster.state = .active
            try booster.setCharge(.capBooster800)
            let drones = try hullA.drones.add(.hammerheadII)
            drones.isActive = true

            let pilotB = try fit.pilots.add(skillLevel: 5)
            let hullB = pilotB.hull
            try hullB.set(typeID: .dominix)
            let neut = try hullB.modules.add(.heavyEnergyNeutralizerII)
            neut.state = .active
            neut.target = Self.hullA

            try fit.pilots.add(skillLevel: 5)
            return (offline.id, repairer.id)
        }
        return (engine, ids.0, ids.1)
    }

    @Test("A hull snapshot matches the live read, simulations included")
    func hullMatchesLiveStats() async throws {
        let (engine, _, _) = try await Self.engine()
        let targets = Self.targets

        let (snapshot, dps, volley, tank, sustainable, cap, armament) = await engine.evaluate { stats in
            let hull = stats[Self.hullA]
            return (hull.snapshot(),
                    targets.map { hull.dps(to: $0) },
                    targets.map { hull.volleyDamage(to: $0) },
                    hull.tank(),
                    hull.sustainableTank(),
                    hull.capacitor(),
                    hull.armament)
        }

        #expect(snapshot.armament == armament)
        #expect(targets.map { snapshot.dps(to: $0) } == dps)
        #expect(targets.map { snapshot.volleyDamage(to: $0) } == volley)
        #expect(dps[0] != .zero)
        #expect(snapshot.dps(from: .drones) != .zero)
        #expect(snapshot.tank == tank)
        #expect(snapshot.sustainableTank() == sustainable)

        let snapshotCap = snapshot.capacitor()
        #expect(snapshotCap.averageDrain == cap.averageDrain)
        #expect(snapshotCap.stableLevel == cap.stableLevel)
        #expect(snapshotCap.lastsFor == cap.lastsFor)

        // The incoming neutralizer is part of this hull's capacitor inputs.
        #expect(snapshot.capacitorSimulator.nodes.contains { $0.drain > 0 && $0.recharge == 0 && $0.clipSize == 0 })
        #expect(snapshot.modules.count == 5)
        #expect(snapshot.drones.count == 1)
    }

    @Test("Module snapshots: weapons, non-weapons, inactive weapons")
    func moduleSnapshots() async throws {
        let (engine, offlineTurret, repairer) = try await Self.engine()
        let (offline, repair) = await engine.evaluate { stats in
            (stats[offlineTurret].snapshot(), stats[repairer].snapshot())
        }

        let weapon = try #require(offline.weapon)
        #expect(weapon.application == .turret)
        #expect(weapon.volley == .zero)
        #expect(offline.dps() == .zero)
        #expect(offline.charge?.typeID == .fusionM)

        #expect(repair.weapon == nil)
        #expect(repair.repair?.kind == .armor)
        #expect(repair.capUse > 0)
    }

    @Test("Fighter channels in a snapshot match the live read")
    func fighterChannels() async throws {
        let engine = DogmaEngine()
        let droneID = try await engine.edit { fit in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: .thanatos)
            let fighter = try hull.drones.add(.einherjiI)
            fighter.isActive = true
            return fighter.id
        }
        let targets = Self.targets

        let (snapshot, dps, channels) = await engine.evaluate { stats in
            let drone = stats[droneID]
            var channels: [FitStats.Drone.Channel] = []
            drone.forEachWeapon { channel, _ in channels.append(channel) }
            return (drone.snapshot(), targets.map { drone.dps(to: $0) }, channels)
        }

        #expect(targets.map { snapshot.dps(to: $0) } == dps)
        #expect(dps[0] != .zero)
        #expect(Set(snapshot.weapons.keys) == Set(channels))
        #expect(snapshot.weapons[.drone] == nil)
    }

    @Test("A snapshot is detached: editing the fit does not change it")
    func detached() async throws {
        let (engine, offlineTurret, _) = try await Self.engine()

        let before = await engine.evaluate { $0[Self.hullA].snapshot() }
        let again = await engine.evaluate { $0[Self.hullA].snapshot() }
        #expect(before == again)

        try await engine.edit { fit in
            fit[offlineTurret].remove()
        }
        let after = await engine.evaluate { $0[Self.hullA].snapshot() }

        #expect(before.modules.count == 5)
        #expect(after.modules.count == 4)
        #expect(before != after)
    }

    @Test("An attribute snapshot equals the live attributes")
    func attributes() async throws {
        let (engine, _, repairer) = try await Self.engine()

        let (snapshot, live, hp, missing) = await engine.evaluate { stats in
            let module = stats[repairer]
            let snapshot = module.attributes.snapshot()
            let live = snapshot.map { module.attributes[$0.0] }
            return (snapshot, live, module.attributes[.hp, default: .sde],
                    module.attributes[.maxVelocity, default: .sde])
        }

        #expect(snapshot.count > 0)
        #expect(snapshot.map(\.1) == live.compactMap { $0 })
        #expect(snapshot.attributeIDs == snapshot.attributeIDs.sorted { $0.rawValue < $1.rawValue })
        #expect(snapshot[.hp, default: .sde] == hp)
        #expect(snapshot[.maxVelocity] == nil)
        #expect(snapshot[.maxVelocity, default: .sde] == missing)
    }

    @Test("Pilot snapshots: capsule, skills opt-in, whole session")
    func pilots() async throws {
        let (engine, _, _) = try await Self.engine()

        let (session, skills, skillCount) = await engine.evaluate { stats in
            let pilot = stats[Self.pilotC]
            return (stats.snapshot(), pilot.skills.snapshot(), pilot.skills.count)
        }

        #expect(session.pilots.count == 3)
        #expect(session.pilots[0].hull.id == Self.hullA)
        #expect(session.pilots[2].hull.typeID == .capsule)
        #expect(skills.count == skillCount)
        #expect(skills.allSatisfy { $0.level == 5 })
    }
}
