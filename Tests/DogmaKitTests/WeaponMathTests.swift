//
//  WeaponMathTests.swift
//  DogmaKit
//
//  Pure damage-application math (`WeaponMath`): no SDE and no engine, so exact numbers can be pinned.
//

import Foundation
import Testing
@testable import DogmaKit

@Suite("WeaponMath", .setupDebugNames)
struct WeaponMathTests {

    private static func target(angular: Double = 0, velocity: Double = 0,
                               signature: Double = 0, range: Double = 0) -> Target {
        Target(angularVelocity: angular, velocity: velocity, signature: signature, range: range)
    }

    // MARK: - Turret

    private static func turret(_ target: Target) -> Double {
        WeaponMath.turretRelativeDPS(accuracyScore: 0.1,
                                     signatureResolution: 100,
                                     optimal: 10_000,
                                     falloff: 5_000,
                                     to: target)
    }

    @Test("Turret: a perfect target gives full damage plus the wrecking-shot contribution")
    func turretPerfectHit() {
        let mult = Self.turret(Self.target(signature: 100))
        // hitChance == 1 → (1 - 0.01) * ((0.01 + 1) / 2 + 0.49) + 0.01 * 3
        #expect(abs(mult - 1.01505) < 1e-9, "got \(mult)")
    }

    @Test("Turret: angular velocity lowers the multiplier")
    func turretAngularVelocityReducesDamage() {
        let values = [0.0, 0.02, 0.05, 0.1, 0.2].map {
            Self.turret(Self.target(angular: $0, signature: 100))
        }
        for (index, pair) in zip(values, values.dropFirst()).enumerated() {
            #expect(pair.1 < pair.0, "step \(index) does not decrease: \(values)")
        }
    }

    @Test("Turret: target signature offsets angular velocity")
    func turretSignatureCompensatesTracking() {
        let values = [25.0, 50, 100, 400].map {
            Self.turret(Self.target(angular: 0.1, signature: $0))
        }
        for (index, pair) in zip(values, values.dropFirst()).enumerated() {
            #expect(pair.1 > pair.0, "step \(index) does not increase: \(values)")
        }
    }

    @Test("Turret: no range penalty at optimal, a penalty beyond it")
    func turretRange() {
        let inOptimal = Self.turret(Self.target(signature: 100, range: 10_000))
        let atFalloff = Self.turret(Self.target(signature: 100, range: 15_000))
        let far = Self.turret(Self.target(signature: 100, range: 40_000))

        #expect(abs(inOptimal - 1.01505) < 1e-9, "no penalty expected at optimal: \(inOptimal)")
        #expect(atFalloff < inOptimal)
        #expect(far < atFalloff)
        // A turret can be activated at any range; the multiplier only tends to zero.
        #expect(far > 0, "a turret has no hard range cutoff")
    }

    @Test("Turret: without falloff there is no range correction (as in Module)")
    func turretWithoutFalloffIgnoresRange() {
        let near = WeaponMath.turretRelativeDPS(accuracyScore: 0.1, signatureResolution: 100,
                                               optimal: 1_000, falloff: 0,
                                               to: Self.target(signature: 100, range: 1_000))
        let far = WeaponMath.turretRelativeDPS(accuracyScore: 0.1, signatureResolution: 100,
                                              optimal: 1_000, falloff: 0,
                                              to: Self.target(signature: 100, range: 100_000))
        #expect(near == far, "\(near) vs \(far)")
    }

    // MARK: - Missiles

    /// Scourge Heavy Missile: ER 140, EV 85, exponent 0.682.
    private static func missile(_ target: Target) -> Double {
        WeaponMath.missileDamageFactor(explosionRadius: 140,
                                       explosionVelocity: 85,
                                       damageReductionExponent: 0.682,
                                       to: target)
    }

    @Test("Missile: a large stationary target takes full damage")
    func missileFullDamage() {
        #expect(Self.missile(Self.target(signature: 1_000)) == 1)
        #expect(Self.missile(Self.target(velocity: 10, signature: 100_000)) == 1)
    }

    @Test("Missile: against a target smaller than the explosion radius, damage scales by S/E")
    func missileSignatureFactor() {
        let factor = Self.missile(Self.target(signature: 70))
        #expect(abs(factor - 0.5) < 1e-12, "70 / 140 = 0.5, got \(factor)")
    }

    @Test("Missile: target velocity reduces damage, known reference value")
    func missileVelocityFactor() {
        // S/E = 130/140 = 0.9286; (0.9286 * 85 / 400)^0.682
        let factor = Self.missile(Self.target(velocity: 400, signature: 130))
        let expected = pow(130.0 / 140.0 * 85.0 / 400.0, 0.682)
        #expect(abs(factor - expected) < 1e-12, "got \(factor), expected \(expected)")
        #expect(factor > 0.32 && factor < 0.34, "reference ~ 0.331, got \(factor)")
    }

    @Test("Missile: rising target velocity monotonically reduces damage")
    func missileVelocityMonotonic() {
        let values = [100.0, 200, 400, 800, 1_600].map {
            Self.missile(Self.target(velocity: $0, signature: 130))
        }
        for (index, pair) in zip(values, values.dropFirst()).enumerated() {
            #expect(pair.1 < pair.0, "step \(index) does not decrease: \(values)")
        }
    }

    @Test("Missile: a zero exponent disables the velocity correction")
    func missileZeroExponentIgnoresVelocity() {
        let factor = WeaponMath.missileDamageFactor(explosionRadius: 140,
                                                    explosionVelocity: 85,
                                                    damageReductionExponent: 0,
                                                    to: Self.target(velocity: 5_000, signature: 1_000))
        #expect(factor == 1, "got \(factor)")
    }

    // MARK: - Range

    @Test("rangeFactor: 1 at optimal, 0.5 at the falloff edge, 0 beyond 3x falloff")
    func rangeFactorShape() {
        func factor(_ range: Double) -> Double {
            WeaponMath.rangeFactor(optimal: 10_000, falloff: 5_000, to: Self.target(range: range))
        }
        #expect(factor(0) == 1)
        #expect(factor(10_000) == 1)
        #expect(abs(factor(15_000) - 0.5) < 1e-12, "got \(factor(15_000))")
        #expect(abs(factor(20_000) - 0.0625) < 1e-12, "0.5^4, got \(factor(20_000))")
        // The boundary is inclusive; beyond it the result is zero.
        #expect(abs(factor(25_000) - 0.001953125) < 1e-12, "0.5^9, got \(factor(25_000))")
        #expect(factor(25_001) == 0, "beyond optimal + 3x falloff the multiplier is zero")
    }

    @Test("rangeFactor: without falloff there is a hard cutoff beyond optimal")
    func rangeFactorHardCutoff() {
        #expect(WeaponMath.rangeFactor(optimal: 10_000, falloff: 0, to: Self.target(range: 10_000)) == 1)
        #expect(WeaponMath.rangeFactor(optimal: 10_000, falloff: 0, to: Self.target(range: 10_001)) == 0)
    }

    @Test("rangeFactor: with the cap removed there is a tail beyond 3x falloff (turret behavior)")
    func rangeFactorUnrestricted() {
        let value = WeaponMath.rangeFactor(optimal: 10_000, falloff: 5_000,
                                           to: Self.target(range: 40_000), restricted: false)
        #expect(value > 0 && value < 1e-5, "got \(value)")
    }

    // MARK: - Missile flight range

    @Test("missileFlightRange: acceleration plus flight at max speed")
    func missileFlightRange() {
        // Scourge Heavy Missile: 4300 m/s, 6.5 s, mass 1000, agility 0.0001445;
        // acceleration time is negligible, so range ~ speed * flight time.
        let range = WeaponMath.missileFlightRange(velocity: 4_300, flightTime: 6.5,
                                                  mass: 1_000, agility: 0.00014449800378457667)
        #expect(range > 27_900 && range < 27_951, "expected ~27950, got \(range)")
    }

    @Test("missileFlightRange: degenerate parameters give zero")
    func missileFlightRangeDegenerate() {
        #expect(WeaponMath.missileFlightRange(velocity: 0, flightTime: 6.5, mass: 1_000, agility: 1) == 0)
        #expect(WeaponMath.missileFlightRange(velocity: 4_300, flightTime: 0, mass: 1_000, agility: 1) == 0)
        #expect(WeaponMath.missileFlightRange(velocity: 4_300, flightTime: 6.5, mass: 0, agility: 1) == 0)
        #expect(WeaponMath.missileFlightRange(velocity: 4_300, flightTime: 6.5, mass: 1_000, agility: 0) == 0)
    }
}
