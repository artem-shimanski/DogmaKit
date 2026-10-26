//
//  Spool.swift
//  DogmaKit
//

#if os(WASI)
import FoundationEssentials
// Math functions come from libc; elsewhere Foundation re-exports it.
import WASILibc
#else
import Foundation
#endif

/// What spools up on a module; selects the attribute pair.
public enum SpoolKind: Sendable, Hashable, CaseIterable {
    /// Damage: entropic disintegrators (`damageMultiplierBonus{Max,PerCycle}`).
    case damage
    /// Repair: mutadaptive remote repairers (`repairMultiplierBonus{Max,PerCycle}`).
    case repair

    @usableFromInline
    var maxAttributeID: AttributeID {
        switch self {
        case .damage: .damageMultiplierBonusMax
        case .repair: .repairMultiplierBonusMax
        }
    }

    @usableFromInline
    var perCycleAttributeID: AttributeID {
        switch self {
        case .damage: .damageMultiplierBonusPerCycle
        case .repair: .repairMultiplierBonusPerCycle
        }
    }
}

/// How to account for spool-up of modules whose strength grows each cycle (entropic
/// disintegrators, mutadaptive remote repairers).
///
/// The bonus is discrete: after `n` full cycles the multiplier is
/// `1 + min(bonusMax, n · bonusPerCycle)`. `bonusMax` and `bonusPerCycle` are regular
/// attributes, so spool-up lives entirely in the read layer.
public enum SpoolPolicy: Sendable, Hashable {
    /// The module has just started; no bonus. The default.
    case none

    /// Fraction of the maximum bonus, 0…1. Cycles are rounded up, so `.scale(1)` (`.full`)
    /// is a fully spooled module.
    case scale(Double)

    /// Seconds of continuous operation since start. Only full cycles count.
    case time(Double)

    /// A fully spooled module.
    public static let full = SpoolPolicy.scale(1)

    /// Number of completed cycles, capped at the number needed to reach the maximum.
    /// `cycleTime` is the raw cycle time, seconds.
    @usableFromInline
    func cycles(max: Double, perCycle: Double, cycleTime: Double) -> Int {
        guard max > 0, perCycle > 0 else { return 0 }
        let maxCycles = Spool.unerr(max / perCycle).rounded(.up)
        let cycles: Double
        switch self {
        case .none:
            return 0
        case .scale(let scale):
            guard scale > 0 else { return 0 }
            cycles = Spool.unerr(max * Swift.min(scale, 1) / perCycle).rounded(.up)
        case .time(let seconds):
            guard seconds > 0, cycleTime > 0 else { return 0 }
            cycles = Spool.unerr(seconds / cycleTime).rounded(.down)
        }
        return Int(Swift.min(cycles, maxCycles))
    }
}

/// Spool-up state of a module under the chosen policy.
public struct Spool: Sendable, Hashable {
    /// Accumulated multiplier bonus: `0` for a cold module, `maxBonus` when fully spooled.
    public var bonus: Double

    /// Bonus cap (`...BonusMax`, including implants and hull bonuses).
    public var maxBonus: Double

    /// Bonus per cycle (`...BonusPerCycle`).
    public var bonusPerCycle: Double

    /// Completed cycles so far.
    public var cycles: Int

    /// Time taken to accumulate `bonus`, seconds.
    public var time: Double

    /// Damage/repair multiplier, `1 + bonus`.
    @inlinable
    public var multiplier: Double { 1 + bonus }

    /// Whether the module is fully spooled.
    @inlinable
    public var isFull: Bool { bonus >= maxBonus }

    /// `nil` if the module does not spool (`...BonusMax == 0`).
    @usableFromInline
    init?(max: Double, perCycle: Double, cycleTime: Double, policy: SpoolPolicy) {
        guard max > 0, perCycle > 0 else { return nil }
        let cycles = policy.cycles(max: max, perCycle: perCycle, cycleTime: cycleTime)
        self.bonus = Swift.min(max, Double(cycles) * perCycle)
        self.maxBonus = max
        self.bonusPerCycle = perCycle
        self.cycles = cycles
        self.time = Double(cycles) * cycleTime
    }

    /// Removes accumulated floating-point error before rounding cycle counts, so that
    /// `ceil(3.0000000001)` does not add a cycle.
    @usableFromInline
    static func unerr(_ value: Double) -> Double {
        guard value.isFinite, value.magnitude < 1e12 else { return value }
        return (value * 1e9).rounded() / 1e9
    }
}
