//
//  ECM.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 27.07.2026.
//

import Foundation

/// Outgoing jamming of one ECM module, built from `scan*StrengthBonus` attributes (absolute
/// strengths on jammers) and the module's optimal/falloff. See `FitStats.Module.ecm`.
@frozen
public struct ECM: Sendable, Equatable {
    /// Jam strength by target sensor type.
    public var strength: SensorStrength
    /// Optimal range, m.
    public var optimal: Double
    /// Falloff, m.
    public var falloff: Double
    /// Cycle time (jam duration on success), seconds.
    public var cycleTime: Double

    @inlinable
    public init(strength: SensorStrength, optimal: Double, falloff: Double, cycleTime: Double) {
        self.strength = strength
        self.optimal = optimal
        self.falloff = falloff
        self.cycleTime = cycleTime
    }
}

extension ECM {
    /// Chance to break the lock in one activation against a target with `sensorStrength`
    /// at `range` meters. Jams the target's dominant sensor type. The range factor is
    /// `WeaponMath.rangeFactor`, cut off beyond `optimal + 3·falloff`.
    public func jamProbability(against sensorStrength: SensorStrength, at range: Double = 0) -> Double {
        guard let dominant = sensorStrength.dominant, dominant.strength > 0 else { return 0 }
        let factor = WeaponMath.rangeFactor(optimal: optimal,
                                            falloff: falloff,
                                            to: Target(angularVelocity: 0,
                                                       velocity: 0,
                                                       signature: 0,
                                                       range: range))
        guard factor > 0 else { return 0 }
        return min(1, strength[dominant.type] / dominant.strength * factor)
    }
}
