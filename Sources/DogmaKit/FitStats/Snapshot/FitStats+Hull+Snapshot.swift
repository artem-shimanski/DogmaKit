//
//  FitStats+Hull+Snapshot.swift
//  DogmaKit
//

// Expensive simulations are not run while a hull snapshot is taken: it keeps their inputs
// (`capacitorSimulator`, `heatSimulator`, `tankProfile`), and the methods below run them on
// demand, off the engine. Other hulls are referenced by ID only; incoming effects
// (neutralizers, remote reps) are already part of this hull's inputs.

extension FitStats.Hull.Snapshot {
    public func capacity(of slot: Entity.Module.Slot) -> SlotCapacity {
        slots[slot] ?? SlotCapacity(used: 0, total: 0)
    }

    /// Runs the capacitor simulation.
    public func capacitor() -> CapacitorSimulator.Result {
        capacitorSimulator.run()
    }

    /// Runs the overheat simulation.
    public func heat() -> HeatSimulator.Result {
        heatSimulator.run()
    }

    /// See `FitStats.Hull.sustainableTank()`. Runs the capacitor simulation.
    public func sustainableTank() -> Tank {
        tankProfile.sustainableTank(capacitor: capacitor())
    }

    /// Same as `sustainableTank()`, reusing an already computed `capacitor()` result.
    public func sustainableTank(capacitor: CapacitorSimulator.Result) -> Tank {
        tankProfile.sustainableTank(capacitor: capacitor)
    }

    public func dps(from sources: FitStats.Hull.DamageSource = .all,
                    to target: Target = .zero) -> DamageVector {
        armament.dps(from: sources, to: target)
    }

    public func volleyDamage(from sources: FitStats.Hull.DamageSource = .all,
                             to target: Target = .zero) -> DamageVector {
        armament.volleyDamage(from: sources, to: target)
    }
}
