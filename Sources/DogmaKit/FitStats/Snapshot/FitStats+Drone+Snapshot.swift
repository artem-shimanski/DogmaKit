//
//  FitStats+Drone+Snapshot.swift
//  DogmaKit
//

extension FitStats.Drone.Snapshot {
    /// Total volley over all working channels, adjusted for the target.
    public func volleyDamage(to target: Target) -> DamageVector {
        var result = DamageVector.zero
        forEachWeapon { result += $1.volleyDamage(to: target) }
        return result
    }

    /// Total DPS against the target, summed over channels. Zero in kamikaze mode.
    public func dps(to target: Target = .zero) -> DamageVector {
        var result = DamageVector.zero
        forEachWeapon { result += $1.dps(to: target) }
        return result
    }

    /// Iterates `weapons` in channel order, so sums match `FitStats.Drone` exactly.
    public func forEachWeapon(_ body: (FitStats.Drone.Channel, Weapon) -> Void) {
        for channel in FitStats.Drone.Channel.allCases {
            if let weapon = weapons[channel] {
                body(channel, weapon)
            }
        }
    }
}
