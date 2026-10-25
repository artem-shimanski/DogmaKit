//
//  FitStats+Module+Snapshot.swift
//  DogmaKit
//

extension FitStats.Module.Snapshot {
    /// Volley adjusted for the target.
    public func volleyDamage(to target: Target) -> DamageVector {
        weapon?.volleyDamage(to: target) ?? .zero
    }

    public func dps(to target: Target = .zero) -> DamageVector {
        weapon?.dps(to: target) ?? .zero
    }
}
