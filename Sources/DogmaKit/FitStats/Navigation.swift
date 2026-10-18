//
//  Navigation.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 27.07.2026.
//

import Foundation

/// Navigation snapshot of a hull. Stores only raw values; derived ones (align time, warp
/// range) are computed on demand, so `applying(_:)` / `removing(_:)` stay consistent.
@frozen
public struct Navigation: Sendable, Equatable {
    /// Maximum velocity, m/s, including active propulsion modules.
    public var maxVelocity: Double
    /// Mass, kg, including `massAddition` of active propulsion modules.
    public var mass: Double
    /// Inertia modifier (`agility`); lower turns faster.
    public var agility: Double
    /// Signature radius, m, including an active MWD's bloom.
    public var signatureRadius: Double
    /// Warp speed, AU/s (`baseWarpSpeed × warpSpeedMultiplier`).
    public var warpSpeed: Double
    /// Warp capacitor need, GJ/(kg·AU).
    public var warpCapacitorNeed: Double
    /// Capacitor capacity, GJ; used by `maxWarpDistance`.
    public var capacitorCapacity: Double

    @inlinable
    public init(maxVelocity: Double,
                mass: Double,
                agility: Double,
                signatureRadius: Double,
                warpSpeed: Double,
                warpCapacitorNeed: Double,
                capacitorCapacity: Double) {
        self.maxVelocity = maxVelocity
        self.mass = mass
        self.agility = agility
        self.signatureRadius = signatureRadius
        self.warpSpeed = warpSpeed
        self.warpCapacitorNeed = warpCapacitorNeed
        self.capacitorCapacity = capacitorCapacity
    }
}

extension Navigation {
    /// `-ln(0.25)`: a ship enters warp at 75% of its maximum velocity.
    @usableFromInline
    static let alignTimeConstant = 1.3862943611198906

    /// Align time, seconds: `-ln(0.25) · agility · mass / 10⁶`.
    /// `0` if mass or agility is not set.
    @inlinable
    public var alignTime: Double {
        guard agility > 0 && mass > 0 else { return 0 }
        return Self.alignTimeConstant * agility * mass / 1_000_000
    }

    /// Capacitor needed to warp `distance` AU, GJ.
    @inlinable
    public func capacitorNeed(warpingFor distance: Double) -> Double {
        mass * warpCapacitorNeed * distance
    }

    /// Maximum single warp distance from a full capacitor, AU.
    /// `0` if the type cannot warp (`warpCapacitorNeed == 0`).
    @inlinable
    public var maxWarpDistance: Double {
        let need = capacitorNeed(warpingFor: 1)
        guard need > 0 else { return 0 }
        return capacitorCapacity / need
    }
}

/// Propulsion module parameters (afterburner / microwarpdrive), enough to project navigation
/// without recalculating the engine. See `FitStats.Module.propulsion`.
///
/// Boost: `maxVelocity × (1 + speedFactor · speedBoostFactor / 100 / mass)`, where `mass`
/// already includes this module's `massAddition`.
@frozen
public struct Propulsion: Sendable, Equatable {
    /// Thrust: `speedFactor · speedBoostFactor / 100`. The relative velocity gain is `thrust / mass`.
    public var thrust: Double
    /// Mass added to the hull, kg.
    public var massAddition: Double
    /// Signature radius penalty, % (0 for afterburners).
    public var signatureRadiusBonus: Double

    @inlinable
    public init(thrust: Double, massAddition: Double, signatureRadiusBonus: Double) {
        self.thrust = thrust
        self.massAddition = massAddition
        self.signatureRadiusBonus = signatureRadiusBonus
    }
}

extension Navigation {
    /// Navigation with this propulsion module on: mass grows by `massAddition`, velocity is
    /// multiplied by `1 + thrust / newMass`, signature by `1 + signatureRadiusBonus/100`.
    /// Expects an unboosted snapshot (`FitStats.Hull.unboostedNavigation`).
    @inlinable
    public func applying(_ propulsion: Propulsion) -> Navigation {
        var result = self
        result.mass = mass + propulsion.massAddition
        if result.mass > 0 {
            result.maxVelocity = maxVelocity * (1 + propulsion.thrust / result.mass)
        }
        result.signatureRadius = signatureRadius * (1 + propulsion.signatureRadiusBonus / 100)
        return result
    }

    /// Removes a propulsion module's contribution; the inverse of `applying(_:)`. The velocity
    /// multiplier is divided out before subtracting mass, since the engine applied it against
    /// the boosted mass.
    ///
    /// Exact only when a single propulsion module is active: two active ones are stacking
    /// penalized and cannot be removed by dividing out multipliers.
    @inlinable
    public func removing(_ propulsion: Propulsion) -> Navigation {
        var result = self
        if mass > 0 {
            let multiplier = 1 + propulsion.thrust / mass
            if multiplier > 0 { result.maxVelocity = maxVelocity / multiplier }
        }
        let bloom = 1 + propulsion.signatureRadiusBonus / 100
        if bloom > 0 { result.signatureRadius = signatureRadius / bloom }
        result.mass = mass - propulsion.massAddition
        return result
    }
}
