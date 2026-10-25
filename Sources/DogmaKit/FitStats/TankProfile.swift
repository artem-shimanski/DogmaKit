//
//  TankProfile.swift
//  DogmaKit
//

/// Inputs of a hull's tank: passive shield regen and every repair applied to the hull.
/// `tank` and `sustainableTank(capacitor:)` are pure functions of it. See
/// `FitStats.Hull.tankProfile()`.
public struct TankProfile: Sendable, Hashable {

    /// One repair contribution. `capPerSecond == 0` means the repairer does not use
    /// this ship's capacitor (incoming remote reps, capless reps); `sustainableTank`
    /// never throttles those.
    public struct Repairer: Sendable, Hashable {
        public var kind: FitStats.Module.RepairKind
        /// Repair, HP/s.
        public var hpPerSecond: Double
        /// Own capacitor use, GJ/s.
        public var capPerSecond: Double

        public init(kind: FitStats.Module.RepairKind, hpPerSecond: Double, capPerSecond: Double) {
            self.kind = kind
            self.hpPerSecond = hpPerSecond
            self.capPerSecond = capPerSecond
        }

        /// HP per unit of capacitor; the greedy order in `sustainableTank`.
        var effectivity: Double { hpPerSecond / capPerSecond }
    }

    /// Peak passive shield regen, HP/s.
    public var passiveShield: Double
    public var repairers: [Repairer]

    public init(passiveShield: Double, repairers: [Repairer]) {
        self.passiveShield = passiveShield
        self.repairers = repairers
    }

    /// Passive shield regen plus all repairers at full rate, HP/s.
    public var tank: Tank {
        var result = Tank(passiveShield: passiveShield,
                          shieldRepair: 0, armorRepair: 0, hullRepair: 0)
        for repairer in repairers {
            result[repair: repairer.kind] += repairer.hpPerSecond
        }
        return result
    }

    /// Tank the capacitor can sustain indefinitely. Equals `tank` when the capacitor
    /// is stable. Otherwise capacitor-using repairers are added greedily by HP per
    /// capacitor unit while peak recharge allows; the last one may run partially.
    public func sustainableTank(capacitor cap: CapacitorSimulator.Result) -> Tank {
        var result = tank
        guard !cap.isStable else { return result }

        var capUse = cap.averageDrain
        let capRecharge = cap.peakRecharge

        var throttled = repairers.filter { $0.capPerSecond > 0 }
        for repairer in throttled {
            result[repair: repairer.kind] -= repairer.hpPerSecond
            capUse -= repairer.capPerSecond
        }

        throttled.sort { $0.effectivity > $1.effectivity }
        for repairer in throttled {
            if capUse > capRecharge { break }
            let sustainability = min(1.0, (capRecharge - capUse) / repairer.capPerSecond)
            result[repair: repairer.kind] += repairer.hpPerSecond * sustainability
            capUse += repairer.capPerSecond
        }

        return result
    }
}
