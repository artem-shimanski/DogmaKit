//
//  HeatSimulator+Result.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 01.08.2026.
//

#if os(WASI)
import FoundationEssentials
// Math functions come from libc; elsewhere Foundation re-exports it.
import WASILibc
#else
import Foundation
#endif

extension HeatSimulator {

    /// Overheat simulation result.
    public struct Result: Sendable {

        /// Result for one module in a rack.
        public struct Module: Sendable {
            public var id: ModuleID?
            public var slot: Entity.Module.Slot
            public var socket: Int
            /// Initial module HP.
            public var hitPoints: Double
            /// Expected accumulated damage at the end of the simulation.
            public var damageTaken: Double
            /// Standard deviation of the accumulated damage.
            public var damageDeviation: Double
            /// Time when the expected damage reached the module's HP. `nil` if the module
            /// survived the simulation.
            public var burnoutTime: Double?
            /// Standard deviation of the burnout time, seconds.
            public var burnoutDeviation: Double

            @inlinable
            public var isBurnedOut: Bool { burnoutTime != nil }

            @inlinable
            public var remainingHitPoints: Double { Swift.max(0, hitPoints - damageTaken) }

            /// Probability that the module is still alive at `time`, using a normal
            /// approximation of the burnout time (`burnoutTime` / `burnoutDeviation`).
            public func survivalProbability(at time: Double) -> Double {
                guard let burnoutTime else { return 1 }
                guard burnoutDeviation > 0 else { return time < burnoutTime ? 1 : 0 }
                return HeatSimulator.Result.normalCDF((burnoutTime - time) / burnoutDeviation)
            }

            /// Time by which the module burns out with the given probability.
            /// `0.5` is the median (`burnoutTime`).
            public func timeToBurnout(probability: Double) -> Double? {
                guard let burnoutTime else { return nil }
                guard burnoutDeviation > 0 else { return burnoutTime }
                let p = Swift.min(Swift.max(probability, 1e-6), 1 - 1e-6)
                return Swift.max(0, burnoutTime + HeatSimulator.Result.normalQuantile(p) * burnoutDeviation)
            }
        }

        /// A piece of a rack's heat curve with constant heat generation. A new segment starts
        /// whenever a source burns out and `generation` changes.
        public struct HeatSegment: Sendable {
            public var start: Double
            /// Heat at `start`.
            public var initialHeat: Double
            /// Heat generation `g` on this segment. `0` means the rack is cooling.
            public var generation: Double
            public var capacity: Double
            public var dissipationRate: Double

            /// Heat `dt` seconds after the segment start.
            @inlinable
            public func heat(after dt: Double) -> Double {
                if generation > 0 {
                    return capacity + (initialHeat - capacity) * exp(-generation * dt)
                }
                else if dissipationRate > 0 {
                    return initialHeat * exp(-dissipationRate * dt)
                }
                return initialHeat
            }
        }

        /// Heat curve of one rack.
        public struct Rack: Sendable {
            public var slot: Entity.Module.Slot
            public var capacity: Double
            /// Segments in ascending `start` order; the first always starts at zero.
            public var segments: [HeatSegment]

            /// Rack heat at `time` (absolute, 0…`capacity`).
            public func heat(at time: Double) -> Double {
                guard var current = segments.first else { return 0 }
                for segment in segments {
                    if segment.start > time { break }
                    current = segment
                }
                return current.heat(after: Swift.max(0, time - current.start))
            }

            /// Peak heat over the simulation. The curve is monotonic on each segment.
            public var peakHeat: Double {
                var peak = 0.0
                for (index, segment) in segments.enumerated() {
                    peak = Swift.max(peak, segment.initialHeat)
                    if index + 1 < segments.count {
                        peak = Swift.max(peak, segments[index + 1].initialHeat)
                    }
                    else if segment.generation > 0 {
                        peak = Swift.max(peak, segment.capacity)
                    }
                }
                return peak
            }
        }

        /// Modules in the racks, including undamaged ones.
        public var modules: [Module]
        /// Heat curves by rack.
        public var racks: [Rack]
        /// Initial `Fs`: the slot fill ratio at the start.
        public var slotFactor: Double
        /// Simulated duration, seconds.
        public var duration: Double
        /// Whether the simulation hit the horizon or the iteration limit. If so,
        /// `burnoutTime == nil` means "not computed", not "never burns out".
        public var isTruncated: Bool

        public subscript(id: ModuleID) -> Module? {
            modules.first { $0.id == id }
        }

        public func rack(_ slot: Entity.Module.Slot) -> Rack? {
            racks.first { $0.slot == slot }
        }

        /// The first module to burn out.
        public var firstBurnout: Module? {
            modules
                .filter { $0.burnoutTime != nil }
                .min { ($0.burnoutTime ?? .infinity) < ($1.burnoutTime ?? .infinity) }
        }

        /// Time by which anything burns out with the given probability. An estimate: the
        /// minimum of per-module quantiles, not the quantile of the minimum.
        public func timeToBurnout(probability: Double) -> Double? {
            modules.compactMap { $0.timeToBurnout(probability: probability) }.min()
        }
    }
}

// MARK: - Normal distribution

extension HeatSimulator.Result {

    /// Standard normal CDF.
    @usableFromInline
    static func normalCDF(_ x: Double) -> Double {
        0.5 * erfc(-x / 2.0.squareRoot())
    }

    /// Inverse standard normal CDF (Acklam's rational approximation, relative error < 1.15e-9).
    @usableFromInline
    static func normalQuantile(_ p: Double) -> Double {
        let a = [-3.969683028665376e+01, 2.209460984245205e+02, -2.759285104469687e+02,
                  1.383577518672690e+02, -3.066479806614716e+01, 2.506628277459239e+00]
        let b = [-5.447609879822406e+01, 1.615858368580409e+02, -1.556989798598866e+02,
                  6.680131188771972e+01, -1.328068155288572e+01]
        let c = [-7.784894002430293e-03, -3.223964580411365e-01, -2.400758277161838e+00,
                 -2.549732539343734e+00, 4.374664141464968e+00, 2.938163982698783e+00]
        let d = [7.784695709041462e-03, 3.224671290700398e-01,
                 2.445134137142996e+00, 3.754408661907416e+00]

        let low = 0.02425
        let high = 1 - low

        if p < low {
            let q = (-2 * log(p)).squareRoot()
            return (((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]) /
                   ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1)
        }
        else if p <= high {
            let q = p - 0.5
            let r = q * q
            return (((((a[0] * r + a[1]) * r + a[2]) * r + a[3]) * r + a[4]) * r + a[5]) * q /
                   (((((b[0] * r + b[1]) * r + b[2]) * r + b[3]) * r + b[4]) * r + 1)
        }
        else {
            let q = (-2 * log(1 - p)).squareRoot()
            return -(((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]) /
                    ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1)
        }
    }
}
