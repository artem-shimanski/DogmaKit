//
//  Weapon.swift
//  DogmaKit
//

#if os(WASI)
import FoundationEssentials
#else
import Foundation
#endif

/// Damage output of one weapon: a module, or one channel of a drone or fighter squadron
/// (`FitStats.Drone.Channel`). A snapshot of the attributes the hit math needs, so damage
/// against any target is computed without the engine. See `FitStats.Module.weapon` and
/// `FitStats.Drone.weapon(_:)`.
@frozen
public struct Weapon: Sendable, Hashable {

    /// How damage is applied to the target.
    public enum Application: Sendable, Hashable {
        /// Full damage up to `optimal`, none beyond (smartbombs, kamikaze detonation).
        case rangeGate
        /// Tracking and optimal/falloff (`WeaponMath.turretRelativeDPS`).
        case turret
        /// A launched missile: no damage beyond its flight range (`optimal`) or against a
        /// target faster than `missileVelocity`, otherwise the explosion formula.
        case missile
        /// A fighter missile ability: the explosion formula times the optimal/falloff
        /// range factor.
        case fighterMissile
    }

    public var application: Application
    /// Volley of one cycle. Zero while the source does not fire (inactive module,
    /// recalled drone, channel disabled by kamikaze mode).
    public var volley: DamageVector
    /// Time between volleys, seconds. `0` for one-shot weapons: they add to volley
    /// but not to DPS.
    public var cycleTime: Double
    /// Optimal range, m. For missiles, the flight range.
    public var optimal: Double
    /// Falloff, m. `0` means no falloff.
    public var falloff: Double
    /// Turret tracking speed.
    public var accuracyScore: Double
    /// Turret signature resolution, m.
    public var signatureResolution: Double
    /// Explosion radius, m.
    public var explosionRadius: Double
    /// Explosion velocity, m/s.
    public var explosionVelocity: Double
    /// Damage reduction exponent of the explosion formula; `0` disables the velocity term.
    public var damageReductionExponent: Double
    /// Missile velocity, m/s. Used only by `.missile`.
    public var missileVelocity: Double

    @inlinable
    public init(application: Application,
                volley: DamageVector,
                cycleTime: Double,
                optimal: Double = 0,
                falloff: Double = 0,
                accuracyScore: Double = 0,
                signatureResolution: Double = 0,
                explosionRadius: Double = 0,
                explosionVelocity: Double = 0,
                damageReductionExponent: Double = 0,
                missileVelocity: Double = 0) {
        self.application = application
        self.volley = volley
        self.cycleTime = cycleTime
        self.optimal = optimal
        self.falloff = falloff
        self.accuracyScore = accuracyScore
        self.signatureResolution = signatureResolution
        self.explosionRadius = explosionRadius
        self.explosionVelocity = explosionVelocity
        self.damageReductionExponent = damageReductionExponent
        self.missileVelocity = missileVelocity
    }
}

extension Weapon {
    /// Fraction of damage that reaches the target. `target == .zero` means no target,
    /// multiplier 1.
    public func relativeDPS(to target: Target) -> Double {
        guard target != .zero else { return 1 }

        switch application {
        case .rangeGate:
            return optimal >= target.range ? 1 : 0

        case .turret:
            return WeaponMath.turretRelativeDPS(accuracyScore: accuracyScore,
                                                signatureResolution: signatureResolution,
                                                optimal: optimal,
                                                falloff: falloff,
                                                to: target)

        case .missile:
            guard optimal >= target.range else { return 0 }
            // The missile cannot catch the target.
            if target.velocity > 0 && missileVelocity < target.velocity { return 0 }
            return WeaponMath.missileDamageFactor(explosionRadius: explosionRadius,
                                                  explosionVelocity: explosionVelocity,
                                                  damageReductionExponent: damageReductionExponent,
                                                  to: target)

        case .fighterMissile:
            let factor = WeaponMath.missileDamageFactor(explosionRadius: explosionRadius,
                                                        explosionVelocity: explosionVelocity,
                                                        damageReductionExponent: damageReductionExponent,
                                                        to: target)
            return factor * WeaponMath.rangeFactor(optimal: optimal, falloff: falloff, to: target)
        }
    }

    /// Volley adjusted for the target.
    public func volleyDamage(to target: Target = .zero) -> DamageVector {
        let relative = relativeDPS(to: target)
        guard relative > 0 else { return .zero }
        return volley * relative
    }

    /// DPS against the target. Zero for one-shot weapons (`cycleTime == 0`).
    public func dps(to target: Target = .zero) -> DamageVector {
        guard cycleTime > 0 else { return .zero }
        let relative = relativeDPS(to: target)
        guard relative > 0 else { return .zero }
        return volley / cycleTime * relative
    }
}
