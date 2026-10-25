//
//  TargetApplicationTests.swift
//  DogmaKit
//
//  Damage application against a target: turret, launcher, drone and fighter DPS must depend
//  on the target's signature, velocity and range. The checks assert monotonicity rather than
//  exact numbers, which vary with skills and SDE version.
//

import Testing
@testable import DogmaKit

@Suite("Damage application against a target", .setupDebugNames)
struct TargetApplicationTests {

    private static let firstHull = PilotID(1).hull

    private static func total(_ damage: DamageVector) -> Double {
        damage.em + damage.thermal + damage.kinetic + damage.explosive
    }

    private static func expectDecreasing(_ values: [Double], _ label: String) {
        for (index, pair) in zip(values, values.dropFirst()).enumerated() {
            #expect(pair.1 < pair.0, "\(label): step \(index) is not decreasing: \(values)")
        }
    }

    private static func expectIncreasing(_ values: [Double], _ label: String) {
        for (index, pair) in zip(values, values.dropFirst()).enumerated() {
            #expect(pair.1 > pair.0, "\(label): step \(index) is not increasing: \(values)")
        }
    }

    // MARK: - Fit builders

    /// Dominix + one 425mm AutoCannon II with Fusion M.
    private static func turretEngine() async throws -> DogmaEngine {
        let engine = DogmaEngine()
        try await engine.edit { fit in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: .dominix)
            let turret = try hull.modules.add(._425mmAutoCannonII)
            turret.state = .active
            try turret.setCharge(.fusionM)
        }
        return engine
    }

    /// Dominix + one Heavy Missile Launcher II with Scourge Heavy Missile.
    private static func launcherEngine() async throws -> DogmaEngine {
        let engine = DogmaEngine()
        try await engine.edit { fit in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: .dominix)
            let launcher = try hull.modules.add(.heavyMissileLauncherII)
            launcher.state = .active
            try launcher.setCharge(.scourgeHeavyMissile)
        }
        return engine
    }

    /// Dominix + a stack of Hammerhead II in space.
    private static func droneEngine(count: UInt8? = nil) async throws -> DogmaEngine {
        let engine = DogmaEngine()
        try await engine.edit { fit in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: .dominix)
            let drone = try hull.drones.add(.hammerheadII, count: count)
            drone.isActive = true
        }
        return engine
    }

    /// Thanatos + an Einherji I squadron in space.
    private static func fighterEngine() async throws -> DogmaEngine {
        let engine = DogmaEngine()
        try await engine.edit { fit in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: .thanatos)
            let fighter = try hull.drones.add(.einherjiI)
            fighter.isActive = true
        }
        return engine
    }

    /// Thanatos + a Shadow squadron, the only type with the kamikaze ability.
    private static func kamikazeEngine(kamikaze: Bool) async throws -> DogmaEngine {
        let engine = DogmaEngine()
        try await engine.edit { fit in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: .thanatos)
            let fighter = try hull.drones.add(.shadow)
            fighter.isActive = true
            fighter.isKamikaze = kamikaze
        }
        return engine
    }

    // MARK: - DPS readers

    /// Total hi-slot module DPS against each target.
    private static func moduleDPS(_ engine: DogmaEngine, targets: [Target]) async -> [Double] {
        await engine.evaluate(reload: .factored) { stats in
            let hull = stats[Self.firstHull]
            var result = [Double](repeating: 0, count: targets.count)
            hull.modules.forEach(in: .hi) { module in
                for (index, target) in targets.enumerated() {
                    result[index] += Self.total(module.dps(to: target))
                }
            }
            return result
        }
    }

    /// Total drone/fighter volley: `[volleyDamage, kamikazeVolleyDamage]`.
    private static func droneVolley(_ engine: DogmaEngine) async -> [Double] {
        await engine.evaluate { stats in
            let hull = stats[Self.firstHull]
            var result = [0.0, 0.0]
            hull.drones.forEach { drone in
                result[0] += Self.total(drone.volleyDamage)
                result[1] += Self.total(drone.kamikazeVolleyDamage)
            }
            return result
        }
    }

    /// Total drone/fighter DPS against each target.
    private static func droneDPS(_ engine: DogmaEngine, targets: [Target]) async -> [Double] {
        await engine.evaluate { stats in
            let hull = stats[Self.firstHull]
            var result = [Double](repeating: 0, count: targets.count)
            hull.drones.forEach { drone in
                for (index, target) in targets.enumerated() {
                    result[index] += Self.total(drone.dps(to: target))
                }
            }
            return result
        }
    }

    /// DPS of a single fighter weapon channel.
    private static func channelDPS(_ engine: DogmaEngine,
                                   weapon: FitStats.Drone.Channel,
                                   targets: [Target]) async -> [Double] {
        await engine.evaluate { stats in
            let hull = stats[Self.firstHull]
            var result = [Double](repeating: 0, count: targets.count)
            hull.drones.forEach { drone in
                for (index, target) in targets.enumerated() {
                    result[index] += Self.total(drone.dps(of: weapon, to: target))
                }
            }
            return result
        }
    }

    // MARK: - Turret

    @Test("Turret: base DPS is positive, the .zero target applies no correction")
    func turretBaseDPS() async throws {
        let engine = try await Self.turretEngine()
        let dps = await Self.moduleDPS(engine, targets: [.zero])
        #expect(dps[0] > 0, "425mm AutoCannon II with Fusion must deal DPS, got \(dps[0])")
    }

    @Test("Turret: higher target angular velocity lowers DPS")
    func turretAngularVelocity() async throws {
        let engine = try await Self.turretEngine()
        let targets = [0.0, 0.01, 0.03, 0.1, 0.3].map {
            Target(angularVelocity: $0, velocity: 0, signature: 200, range: 1_000)
        }
        let dps = await Self.moduleDPS(engine, targets: targets)
        Self.expectDecreasing(dps, "turret / angular velocity")
    }

    @Test("Turret: larger target signature raises DPS")
    func turretSignature() async throws {
        let engine = try await Self.turretEngine()
        let targets = [50.0, 100, 200, 400, 1_000].map {
            Target(angularVelocity: 0.1, velocity: 0, signature: $0, range: 1_000)
        }
        let dps = await Self.moduleDPS(engine, targets: targets)
        Self.expectIncreasing(dps, "turret / signature")
    }

    @Test("Turret: greater range lowers DPS, almost nothing past falloff")
    func turretRange() async throws {
        let engine = try await Self.turretEngine()
        let targets = [10_000.0, 20_000, 40_000, 80_000].map {
            Target(angularVelocity: 0, velocity: 0, signature: 200, range: $0)
        }
        let dps = await Self.moduleDPS(engine, targets: targets)
        Self.expectDecreasing(dps, "turret / range")

        let extremes = await Self.moduleDPS(engine, targets: [Target.zero, targets[targets.count - 1]])
        #expect(extremes[1] < extremes[0] * 0.01,
                "DPS at 80 km must be negligible: \(extremes[1]) vs \(extremes[0]) at point blank")
    }

    // MARK: - Launcher

    @Test("Launcher: base DPS is positive")
    func launcherBaseDPS() async throws {
        let engine = try await Self.launcherEngine()
        let dps = await Self.moduleDPS(engine, targets: [.zero])
        #expect(dps[0] > 0, "Heavy Missile Launcher II with Scourge must deal DPS, got \(dps[0])")
    }

    @Test("Launcher: higher target velocity lowers DPS")
    func launcherTargetVelocity() async throws {
        let engine = try await Self.launcherEngine()
        let targets = [0.0, 500, 1_500, 3_000].map {
            Target(angularVelocity: 0, velocity: $0, signature: 100, range: 5_000)
        }
        let dps = await Self.moduleDPS(engine, targets: targets)
        Self.expectDecreasing(dps, "launcher / target velocity")
    }

    @Test("Launcher: larger target signature raises DPS up to full damage")
    func launcherSignature() async throws {
        let engine = try await Self.launcherEngine()
        let targets = [50.0, 100, 200, 400, 800].map {
            Target(angularVelocity: 0, velocity: 1_000, signature: $0, range: 5_000)
        }
        let dps = await Self.moduleDPS(engine, targets: targets)
        Self.expectIncreasing(dps, "launcher / signature")

        // A huge slow target applies no correction; damage equals the raw value.
        let saturated = await Self.moduleDPS(engine, targets: [
            Target.zero,
            Target(angularVelocity: 0, velocity: 10, signature: 100_000, range: 5_000)
        ])
        #expect(abs(saturated[1] - saturated[0]) < saturated[0] * 1e-9,
                "missiles must deal full damage to a huge slow target: \(saturated)")
    }

    @Test("Launcher: DPS is zero beyond flight range")
    func launcherOutOfRange() async throws {
        let engine = try await Self.launcherEngine()
        let dps = await Self.moduleDPS(engine, targets: [
            Target(angularVelocity: 0, velocity: 0, signature: 1_000, range: 5_000),
            Target(angularVelocity: 0, velocity: 0, signature: 1_000, range: 500_000)
        ])
        #expect(dps[0] > 0, "damage within flight range")
        #expect(dps[1] == 0, "no damage beyond flight range, got \(dps[1])")
    }

    @Test("Launcher: target angular velocity does not affect missiles")
    func launcherIgnoresAngularVelocity() async throws {
        let engine = try await Self.launcherEngine()
        let dps = await Self.moduleDPS(engine, targets: [
            Target(angularVelocity: 0, velocity: 300, signature: 100, range: 5_000),
            Target(angularVelocity: 1, velocity: 300, signature: 100, range: 5_000)
        ])
        #expect(dps[0] > 0)
        #expect(dps[0] == dps[1], "missiles do not depend on tracking: \(dps)")
    }

    // MARK: - Drones

    @Test("Drone: base DPS is positive")
    func droneBaseDPS() async throws {
        let engine = try await Self.droneEngine()
        let dps = await Self.droneDPS(engine, targets: [.zero])
        #expect(dps[0] > 0, "Hammerhead II in space must deal DPS, got \(dps[0])")
    }

    @Test("Drone: higher target angular velocity lowers DPS")
    func droneAngularVelocity() async throws {
        let engine = try await Self.droneEngine()
        let targets = [0.0, 0.05, 0.2, 0.5].map {
            Target(angularVelocity: $0, velocity: 0, signature: 100, range: 1_000)
        }
        let dps = await Self.droneDPS(engine, targets: targets)
        Self.expectDecreasing(dps, "drone / angular velocity")
    }

    @Test("Drone: larger target signature raises DPS")
    func droneSignature() async throws {
        let engine = try await Self.droneEngine()
        let targets = [25.0, 50, 100, 200, 400].map {
            Target(angularVelocity: 0.3, velocity: 0, signature: $0, range: 1_000)
        }
        let dps = await Self.droneDPS(engine, targets: targets)
        Self.expectIncreasing(dps, "drone / signature")
    }

    @Test("Drone: greater range lowers DPS")
    func droneRange() async throws {
        let engine = try await Self.droneEngine()
        let targets = [5_000.0, 8_000, 12_000, 20_000].map {
            Target(angularVelocity: 0, velocity: 0, signature: 100, range: $0)
        }
        let dps = await Self.droneDPS(engine, targets: targets)
        Self.expectDecreasing(dps, "drone / range")
    }

    @Test("Drone: target correction is independent of stack size, DPS scales linearly")
    func droneCountScalesLinearly() async throws {
        let target = Target(angularVelocity: 0.2, velocity: 0, signature: 100, range: 3_000)

        let single = try await Self.droneEngine(count: 1)
        let stack = try await Self.droneEngine(count: 5)

        let dps1 = await Self.droneDPS(single, targets: [target])
        let dps5 = await Self.droneDPS(stack, targets: [target])

        #expect(dps1[0] > 0)
        #expect(abs(dps5[0] - dps1[0] * 5) < dps1[0] * 1e-9,
                "a stack of 5 drones must give exactly 5x: \(dps5[0]) vs \(dps1[0] * 5)")
    }

    // MARK: - Fighters

    @Test("Fighter: DPS is computed per channel, not from rawCycleTime")
    func fighterHasDPS() async throws {
        let engine = try await Self.fighterEngine()

        // Fighter ability durations live in fighterAbility*Duration, so rawCycleTime is zero;
        // DPS must be computed per channel or it would be zero.
        let cycles = await engine.evaluate { stats in
            let hull = stats[Self.firstHull]
            var result = [0.0, 0.0]
            hull.drones.forEach { drone in
                result[0] += drone.rawCycleTime
                result[1] += drone.cycleTime(of: .fighterAttackMissile)
            }
            return result
        }
        #expect(cycles[0] == 0,
                "Einherji I has no duration/speed, expected zero rawCycleTime, got \(cycles[0])")
        #expect(cycles[1] > 0,
                "fighterAbilityAttackMissileDuration must give a cycle time, got \(cycles[1])")

        let dps = await Self.droneDPS(engine, targets: [.zero])
        #expect(dps[0] > 0, "an Einherji I squadron must deal DPS, got \(dps[0])")
    }

    @Test("Fighter: a fast small target takes far less damage")
    func fighterTargetVelocity() async throws {
        let engine = try await Self.fighterEngine()
        let dps = await Self.channelDPS(engine, weapon: .fighterAttackMissile, targets: [
            Target(angularVelocity: 0, velocity: 10, signature: 10_000, range: 2_000),
            Target(angularVelocity: 0, velocity: 400, signature: 130, range: 2_000),
            Target(angularVelocity: 0, velocity: 1_200, signature: 130, range: 2_000)
        ])
        #expect(dps[0] > 0)
        Self.expectDecreasing(dps, "fighter / target velocity")
        #expect(dps[1] < dps[0] * 0.5,
                "fighter missiles must lose over half their damage against a frigate at 400 m/s: \(dps)")
    }

    @Test("Fighter: larger target signature raises DPS")
    func fighterSignature() async throws {
        let engine = try await Self.fighterEngine()
        let targets = [30.0, 60, 130, 300].map {
            Target(angularVelocity: 0, velocity: 500, signature: $0, range: 2_000)
        }
        let dps = await Self.channelDPS(engine, weapon: .fighterAttackMissile, targets: targets)
        Self.expectIncreasing(dps, "fighter / signature")
    }

    // MARK: - Kamikaze mode

    @Test("Kamikaze: the mode is exclusive with the normal attack")
    func kamikazeIsExclusive() async throws {
        let normal = try await Self.kamikazeEngine(kamikaze: false)
        let ramming = try await Self.kamikazeEngine(kamikaze: true)

        let normalDPS = await Self.droneDPS(normal, targets: [.zero])
        let normalVolley = await Self.droneVolley(normal)
        let rammingDPS = await Self.droneDPS(ramming, targets: [.zero])
        let rammingVolley = await Self.droneVolley(ramming)

        // Outside the mode: regular DPS, no detonation damage mixed in.
        #expect(normalDPS[0] > 0, "Shadow outside kamikaze mode must deal DPS")
        #expect(normalVolley[1] == 0,
                "detonation must not count outside the mode, got \(normalVolley[1])")
        // Regular Shadow volley is 400 x 6 = 2400; a full-squadron detonation is 1,200,000.
        #expect(normalVolley[0] > 0 && normalVolley[0] < 100_000,
                "the volley outside the mode is the regular attack, not a detonation: \(normalVolley[0])")

        // In the mode: no DPS, all damage in a single volley.
        #expect(rammingDPS[0] == 0,
                "no sustained DPS in kamikaze mode, got \(rammingDPS[0])")
        #expect(rammingVolley[1] > 0, "the detonation must deal damage")
        #expect(rammingVolley[0] == rammingVolley[1],
                "in kamikaze mode the whole volley is the detonation: \(rammingVolley)")
        #expect(rammingVolley[1] > normalVolley[0] * 10,
                "the detonation is orders of magnitude stronger than the regular volley: \(rammingVolley[1]) vs \(normalVolley[0])")
    }

    @Test("Kamikaze: detonation damage scales with squadron size")
    func kamikazeScalesWithSquadron() async throws {
        func volley(count: UInt8) async throws -> Double {
            let engine = DogmaEngine()
            try await engine.edit { fit in
                let pilot = try fit.pilots.add(skillLevel: 5)
                let hull = pilot.hull
                try hull.set(typeID: .thanatos)
                let fighter = try hull.drones.add(.shadow, count: count)
                fighter.isActive = true
                fighter.isKamikaze = true
            }
            return await Self.droneVolley(engine)[1]
        }

        let single = try await volley(count: 1)
        let squadron = try await volley(count: 3)
        #expect(single > 0)
        #expect(abs(squadron - single * 3) < single * 1e-9,
                "a squadron of 3 must give exactly 3x: \(squadron) vs \(single * 3)")
    }

    @Test("Kamikaze: the detonation is limited by its own range")
    func kamikazeRange() async throws {
        let engine = try await Self.kamikazeEngine(kamikaze: true)
        let volleys = await engine.evaluate { stats in
            let hull = stats[Self.firstHull]
            var result = [0.0, 0.0, 0.0]
            hull.drones.forEach { drone in
                result[0] += drone.optimal(of: .kamikaze)
                result[1] += Self.total(drone.volleyDamage(of: .kamikaze,
                                                           to: Target(angularVelocity: 0, velocity: 0,
                                                                      signature: 1_000, range: 100)))
                result[2] += Self.total(drone.volleyDamage(of: .kamikaze,
                                                           to: Target(angularVelocity: 0, velocity: 0,
                                                                      signature: 1_000, range: 100_000)))
            }
            return result
        }
        #expect(volleys[0] > 0, "the detonation must have a range (fighterAbilityKamikazeRange)")
        #expect(volleys[1] > 0, "the detonation deals damage at point blank")
        #expect(volleys[2] == 0, "no damage beyond detonation range, got \(volleys[2])")
    }

    @Test("Kamikaze: the mode cannot be enabled on a plain drone")
    func kamikazeUnavailableForPlainDrone() async throws {
        let engine = DogmaEngine()
        let flags = try await engine.edit { fit in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: .dominix)
            let drone = try hull.drones.add(.hammerheadII)
            drone.isActive = true
            drone.isKamikaze = true      // no ability, so enabling is ignored
            return [drone.hasKamikazeAbility, drone.isKamikaze]
        }
        #expect(flags[0] == false, "Hammerhead II has no kamikaze ability")
        #expect(flags[1] == false, "the mode must not enable without the ability")

        // DPS stays regular.
        let dps = await Self.droneDPS(engine, targets: [.zero])
        #expect(dps[0] > 0, "a plain drone keeps firing, got \(dps[0])")
    }

    @Test("Fighter: DPS is zero beyond ability range")
    func fighterOutOfRange() async throws {
        let engine = try await Self.fighterEngine()
        let dps = await Self.droneDPS(engine, targets: [
            Target(angularVelocity: 0, velocity: 0, signature: 1_000, range: 2_000),
            Target(angularVelocity: 0, velocity: 0, signature: 1_000, range: 500_000)
        ])
        #expect(dps[0] > 0, "damage within range")
        #expect(dps[1] == 0, "no damage beyond optimal + 3x falloff, got \(dps[1])")
    }
}
