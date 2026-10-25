//
//  ExtractorProgram.swift
//  DogmaPlanetary
//
//  Created by Artem Shimanski on 14.10.2026.
//

import Foundation

/// Extractor control unit (ECU) program: the output of every cycle from installation to expiry.
///
/// The formula is CCP's reference (`esi/esi-docs`, `snippets/formulae/pi-extraction.*`). The output of cycle `i`
/// (from zero at `installTime`) depends only on `quantityPerCycle`, the cycle length and two SDE constants; head
/// positions and resource density are already folded into the `qty_per_cycle` that ESI returns.
///
/// Time is kept in whole seconds from `installTime`: ESI dates have one-second precision.
public struct ExtractorProgram: Hashable, Sendable {
    public var installTime: Date
    public var expiryTime: Date
    /// Seconds (ESI `extractor_details.cycle_time`).
    public var cycleTime: Int
    /// ESI `extractor_details.qty_per_cycle`, used in the formula as is.
    public var quantityPerCycle: Int
    /// `ecuDecayFactor` (1683); see `PlanetaryCatalog.extractor`.
    public var decayFactor: Double
    /// `ecuNoiseFactor` (1687).
    public var noiseFactor: Double

    public init(installTime: Date, expiryTime: Date, cycleTime: Int, quantityPerCycle: Int,
                decayFactor: Double, noiseFactor: Double) {
        self.installTime = installTime
        self.expiryTime = expiryTime
        self.cycleTime = cycleTime
        self.quantityPerCycle = quantityPerCycle
        self.decayFactor = decayFactor
        self.noiseFactor = noiseFactor
    }

    /// The constants come from the catalog: they live in the SDE, and CCP warns they may change.
    public init(installTime: Date, expiryTime: Date, cycleTime: Int, quantityPerCycle: Int,
                constants: DogmaPlanetaryData.ExtractorConstants) {
        self.init(installTime: installTime, expiryTime: expiryTime, cycleTime: cycleTime,
                  quantityPerCycle: quantityPerCycle,
                  decayFactor: constants.decayFactor, noiseFactor: constants.noiseFactor)
    }

    /// Program duration in seconds. Rounded rather than truncated: dates arrive in whole seconds, and the difference of two `Date`s may fall an ulp short of an integer.
    public var duration: Int {
        max(0, Int(expiryTime.timeIntervalSince(installTime).rounded()))
    }

    /// Number of whole cycles: `(expiry - install) / cycleTime`, integer division as in CCP's reference. A partial tail yields no cycle.
    public var cycleCount: Int {
        guard cycleTime > 0, quantityPerCycle > 0 else { return 0 }
        return duration / cycleTime
    }

    // MARK: - Output

    /// Cycle output before rounding (as the Python variant of the reference returns it). Zero outside `0..<cycleCount`.
    ///
    /// The expressions follow the reference literally (`t * (1 / 12)`, not `t / 12`): the result is truncated to an
    /// integer afterwards, and a difference in the last bit of the `Double` would occasionally give +-1.
    public func rawYield(cycle: Int) -> Double {
        guard (0..<cycleCount).contains(cycle) else { return 0 }
        let quantity = Double(quantityPerCycle)
        let barWidth = Double(cycleTime) / 900          // cycle length in 15-minute units
        let t = (Double(cycle) + 0.5) * barWidth
        let decay = quantity / (1 + t * decayFactor)
        let phaseShift = pow(quantity, 0.7)
        let a = cos(phaseShift + t * (1.0 / 12.0))
        let b = cos(phaseShift / 2 + t * 0.2)
        let c = cos(t * 0.5)
        let noise = max((a + b + c) / 3, 0)
        return barWidth * decay * (1 + noiseFactor * noise)
    }

    /// Cycle output in product units: `rawYield` truncated toward zero, as in the C# variant of CCP's reference.
    /// The Kotlin variant subtracts 1 from integer values; which one matches the server is unverified.
    public func yield(cycle: Int) -> Int {
        Int(rawYield(cycle: cycle))
    }

    /// Output of all cycles in order, for charting the program.
    public var yields: [Int] {
        (0..<cycleCount).map { yield(cycle: $0) }
    }

    /// Total output of the program.
    public var totalYield: Int {
        (0..<cycleCount).reduce(0) { $0 + yield(cycle: $1) }
    }

    // MARK: - Time

    public func cycleStart(_ cycle: Int) -> Date {
        installTime.addingTimeInterval(TimeInterval(cycle * cycleTime))
    }

    /// When the cycle ends; its output goes out through routes at that moment.
    public func cycleEnd(_ cycle: Int) -> Date {
        cycleStart(cycle + 1)
    }

    /// The cycle running at `date` (start inclusive, end exclusive), or `nil` outside the program.
    public func cycle(at date: Date) -> Int? {
        guard cycleTime > 0 else { return nil }
        let elapsed = date.timeIntervalSince(installTime)
        guard elapsed >= 0 else { return nil }
        let cycle = Int((elapsed / Double(cycleTime)).rounded(.down))
        return cycle < cycleCount ? cycle : nil
    }

    /// Output of the cycles that COMPLETED in the half-open interval `(from, to]`: "how much was extracted in the
    /// window". A cycle ending exactly at `from` belongs to the previous window.
    public func yield(from: Date, to: Date) -> Int {
        let range = completedCycles(from: from, to: to)
        return range.reduce(0) { $0 + yield(cycle: $1) }
    }

    /// Indices of the cycles that completed in `(from, to]`.
    public func completedCycles(from: Date, to: Date) -> Range<Int> {
        guard cycleTime > 0, to > from else { return 0..<0 }
        let ct = Double(cycleTime)
        // Cycle i ends at install + (i + 1)*ct. The condition from < end <= to is
        // floor(a) <= i <= floor(b) - 1, where a, b are the offsets of from/to in cycles.
        let a = (from.timeIntervalSince(installTime) / ct).rounded(.down)
        let b = (to.timeIntervalSince(installTime) / ct).rounded(.down)
        let lower = max(0, Int(max(a, -1)))
        let upper = min(cycleCount, Int(max(b, 0)))
        return lower < upper ? lower..<upper : 0..<0
    }
}
