//
//  WeaponMath.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 27.07.2026.
//

#if os(WASI)
import FoundationEssentials
// Math functions come from libc; elsewhere Foundation re-exports it.
import WASILibc
#else
import Foundation
#endif

/// Pure hit and damage-reduction math, shared by `FitStats.Module` and `FitStats.Drone`
/// (fighters use the same formulas with `fighterAbility*` attributes).
enum WeaponMath {

    /// Average turret damage multiplier against the target: tracking (angular velocity vs.
    /// tracking speed, adjusted for signature) and range (optimal/falloff). Includes wrecking
    /// shots (x3), so the result can exceed the hit chance. `falloff == 0` means no falloff.
    static func turretRelativeDPS(accuracyScore: Double,
                                  signatureResolution: Double,
                                  optimal: Double,
                                  falloff: Double,
                                  to target: Target) -> Double {
        var a = 0.0
        if target.angularVelocity > 0 && accuracyScore > 0 {
            a = target.angularVelocity / accuracyScore
        }
        if target.signature > 0 && signatureResolution > 0 {
            a *= signatureResolution / target.signature
        }

        var b = 0.0
        if target.range > 0 {
            b = falloff > 0 ? max(0.0, (target.range - optimal) / falloff) : 0
        }

        let blob = a * a + b * b
        let hitChance = exp2(-blob)

        return hitChance > 0.01
        ? (hitChance - 0.01) * (0.5 + (hitChance + 0.49)) / 2 + 0.01 * 3
        : hitChance * 3
    }

    /// Damage fraction of an explosive volley (missile / bomb / fighter missile):
    /// `min(1, S/E, (S/E · Ve/Vt)^dre)`, where `E` is the explosion radius, `Ve` the explosion
    /// velocity, `S`/`Vt` the target's signature and velocity.
    static func missileDamageFactor(explosionRadius: Double,
                                    explosionVelocity: Double,
                                    damageReductionExponent dre: Double,
                                    to target: Target) -> Double {
        var a = 1.0
        if target.signature > 0 {
            a = explosionRadius != 0 ? target.signature / explosionRadius : 1
        }
        var b = 1.0
        if target.velocity > 0 && dre > 0 {
            b = pow(a * explosionVelocity / target.velocity, dre)
        }
        return min(1.0, min(a, b))
    }

    /// Range multiplier for weapons without tracking (fighter missile abilities, EWAR):
    /// `0.5^((max(0, d − optimal)/falloff)²)`. `falloff == 0` is a hard cutoff past optimal.
    /// `restricted`: the module cannot be activated beyond `optimal + 3·falloff`.
    static func rangeFactor(optimal: Double, falloff: Double, to target: Target,
                            restricted: Bool = true) -> Double {
        guard target.range > optimal else { return 1 }
        guard falloff > 0 else { return 0 }
        if restricted && target.range > optimal + 3 * falloff { return 0 }
        let x = (target.range - optimal) / falloff
        return exp2(-x * x)
    }

    /// Missile flight range: acceleration (`mass · agility`) plus flight at full velocity for
    /// the rest of its lifetime. `velocity` and `flightTime` (seconds) include launcher multipliers.
    static func missileFlightRange(velocity: Double,
                                   flightTime: Double,
                                   mass: Double,
                                   agility: Double) -> Double {
        guard velocity > 0 && flightTime > 0 && mass > 0 && agility > 0 else { return 0 }
        let accelerationTime = min(flightTime, mass * agility / 1_000_000)
        let acceleration = velocity / 2.0 * accelerationTime
        let fullSpeed = velocity * (flightTime - accelerationTime)
        return acceleration + fullSpeed
    }
}
