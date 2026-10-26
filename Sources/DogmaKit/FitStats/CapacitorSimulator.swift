//
//  CapacitorSimulator.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 08.07.2026.
//

#if os(WASI)
import FoundationEssentials
// Math functions come from libc; elsewhere Foundation re-exports it.
import WASILibc
#else
import Foundation
#endif

/// Capacitor stability simulator.
///
/// EVE's capacitor follows `dC/dt = (10·Cmax/τ)·(√(C/Cmax) − C/Cmax)`, where `τ` is
/// `rechargeRate`. Peak regen `2.5·Cmax/τ` is reached at 25% charge. With `u = √(C/Cmax)`
/// the equation becomes linear: `u(t+Δt) = 1 − (1 − u(t))·exp(−5·Δt/τ)`, the exact solution
/// of free recharge between discrete events (module cycles).
///
/// The simulation is event-driven, starting from a full capacitor: every node first fires
/// at `t = 0`, activations within a clip are `cycleTime` apart, and after `clipSize`
/// activations a discrete `reloadTime` gap is inserted.
public struct CapacitorSimulator: Sendable, Equatable {

    /// A periodic event affecting the capacitor.
    public struct Node: Sendable, Equatable {
        /// Time between activations within a clip, seconds (raw cycle + reactivation).
        public var cycleTime: Double
        
        /// Charge consumed per activation.
        public var drain: Double
        /// Charge injected per activation (cap booster, remote capacitor transmitter).
        public var recharge: Double
        /// Activations before a reload. `0` means no reload (continuous cycle).
        public var clipSize: Int
        /// Discrete reload gap after a clip, seconds.
        public var reloadTime: Double

        public var averageDrain: Double
        public var averageRecharge: Double

        @inlinable
        public init(cycleTime: Double, drain: Double, recharge: Double, clipSize: Int = 0, reloadTime: Double = 0) {
            self.cycleTime = cycleTime
            self.drain = drain
            self.recharge = recharge
            self.clipSize = clipSize
            self.reloadTime = reloadTime
            
            if cycleTime > 0 {
                if clipSize > 0 {
                    let activations = Double(clipSize)
                    let clipDuration = activations * cycleTime + reloadTime
                    averageDrain = clipDuration > 0 ? drain * activations / clipDuration : 0
                    averageRecharge = clipDuration > 0 ? recharge * activations / clipDuration : 0
                } else {
                    averageDrain = drain / cycleTime
                    averageRecharge = recharge / cycleTime
                }
            }
            else {
                averageDrain = 0
                averageRecharge = 0
            }
        }

        /// A continuous node without reloads.
        @inlinable
        public init(period: Double, drain: Double, recharge: Double) {
            self.init(cycleTime: period, drain: drain, recharge: recharge, clipSize: 0, reloadTime: 0)
        }
    }

    /// Simulation result.
    public struct Result: Sendable {
        /// Capacitor capacity, GJ.
        public var capacity: Double
        /// Recharge time τ, seconds.
        public var rechargeTime: Double
        /// Peak recharge rate `2.5·Cmax/τ`, GJ/s.
        public var peakRecharge: Double
        /// Average drain over all nodes, GJ/s.
        public var averageDrain: Double
        /// Average recharge including injections, GJ/s.
        public var averageRecharge: Double
        
        /// Margin: `peakRecharge − averageDrain`, GJ/s. `≥ 0` means the capacitor can be stable.
        public var delta: Double
        
        /// Whether the capacitor is stable (did not run dry within the simulation horizon).
        public var isStable: Bool {
            stableLevel != nil
        }
        /// Stable charge level (0…1), the analytic solution of `recharge(C) = drain`.
        /// `nil` if unstable.
        public var stableLevel: Double?
        /// Lowest charge level (0…1) reached during the simulation.
        public var minimumLevel: Double
        /// Time until the capacitor runs dry, seconds. `.infinity` if stable.
        public var lastsFor: Double
    }

    /// Capacitor capacity Cmax, GJ.
    public var capacity: Double
    /// Recharge time τ, seconds.
    public var rechargeTime: Double
    /// Periodic consumers and injectors.
    public var nodes: [Node]

    @inlinable
    public init(capacity: Double, rechargeTime: Double, nodes: [Node]) {
        self.capacity = capacity
        self.rechargeTime = rechargeTime
        self.nodes = nodes
    }

    /// Maximum simulation time for an unstable fit, seconds (6 hours).
    static let maxSimulationTime: Double = 6 * 3600
    /// Safety limit on the number of events.
    static let maxIterations = 2_000_000

    public func run() -> Result {
        var drain = 0.0
        var recharge = 0.0
        for node in nodes {
            drain += node.averageDrain
            recharge += node.averageRecharge
        }
        let flow = recharge - drain
        
        guard capacity > 0, rechargeTime > 0 else {
            // No capacitor: trivially stable.
            return Result(capacity: capacity, rechargeTime: rechargeTime,
                          peakRecharge: 0, averageDrain: drain, averageRecharge: recharge,
                          delta: flow,
                          stableLevel: flow >= 0 ? 1 : nil,
                          minimumLevel: flow >= 0 ? 1 : 0,
                          lastsFor: flow >= 0 ? .infinity : 0)
        }

        let peakRecharge = 2.5 * capacity / rechargeTime
        let delta = peakRecharge + flow
        let fullRecharge = recharge + peakRecharge

            // Fast path: no drain, the capacitor is always full.
        if drain == 0 {
            return Result(capacity: capacity, rechargeTime: rechargeTime,
                          peakRecharge: peakRecharge, averageDrain: drain, averageRecharge: fullRecharge, delta: delta, stableLevel: 1, minimumLevel: 1,
                          lastsFor: .infinity)
        }

        // Analytic stable level (upper root of u² − u + k = 0).
        let analyticStableLvl = Self.stableLevel(averageFlow: flow,
                                                 capacity: capacity,
                                                 rechargeTime: rechargeTime)
        let analyticallyStable = analyticStableLvl != nil

        // For an analytically stable fit a few τ are enough for the transient to settle.
        let horizon = analyticallyStable
            ? min(max(rechargeTime * 6, 300), Self.maxSimulationTime)
            : Self.maxSimulationTime

        let sim = simulate(horizon: horizon)

        if sim.depleted {
            return Result(capacity: capacity, rechargeTime: rechargeTime,
                          peakRecharge: peakRecharge, averageDrain: drain, averageRecharge: fullRecharge,  delta: delta,
                          stableLevel: nil,
                          minimumLevel: 0, lastsFor: sim.time)
        } else {
            return Result(capacity: capacity, rechargeTime: rechargeTime,
                          peakRecharge: peakRecharge, averageDrain: drain, averageRecharge: fullRecharge, delta: delta,
                          stableLevel: analyticStableLvl,
                          minimumLevel: sim.minCap / capacity,
                          lastsFor: .infinity)
        }
    }

    /// Analytic stable charge level, or `nil` if unstable.
    static func stableLevel(averageFlow: Double, capacity: Double, rechargeTime: Double) -> Double? {
        guard capacity > 0, rechargeTime > 0 else { return nil }
        if averageFlow >= 0 { return 1 }
        // recharge(C) = (10·Cmax/τ)·u·(1−u) = drain, u = √(C/Cmax).
        // u² − u + k = 0, k = drain·τ/(10·Cmax).
        let k = -averageFlow * rechargeTime / (10 * capacity)
        let discriminant = 1 - 4 * k
        guard discriminant >= 0 else { return nil } // drain exceeds peak recharge
        let u = (1 + discriminant.squareRoot()) / 2 // upper root: the level reached from full
        return u * u
    }

    private struct State {
        var cycleTime: Double
        var amount: Double
        var clipSize: Int
        var reloadTime: Double
        var tNext: Double = 0   // first activation at t = 0
        var shot: Int = 0
    }

    /// Event-driven simulation from a full capacitor. Returns whether the capacitor ran dry,
    /// when, and the lowest charge. `observe` receives every activation: its time and the
    /// charge right before and after it (the last one may be negative when it runs dry).
    func simulate(horizon: Double,
                  observe: ((_ time: Double, _ before: Double, _ after: Double) -> Void)? = nil)
        -> (depleted: Bool, time: Double, minCap: Double) {
        var states: [State] = []
        states.reserveCapacity(nodes.count)
        for node in nodes where node.cycleTime > 0 {
            let amount = node.recharge - node.drain
            guard amount != 0 else {continue}
            states.append(State(cycleTime: node.cycleTime, amount: amount,
                                clipSize: node.clipSize, reloadTime: node.reloadTime))
        }
        guard !states.isEmpty else { return (false, .infinity, capacity) }

        let tau = rechargeTime
        var cap = capacity
        var minCap = capacity
        var minCapPre = capacity
        var tLast = 0.0
        var iterations = 0

        while true {
            iterations += 1
            if iterations > Self.maxIterations { break }

            // Next event.
            var next = Double.greatestFiniteMagnitude
            var idx = -1
            for i in states.indices where states[i].tNext < next {
                next = states[i].tNext
                idx = i
            }
            if idx < 0 || next > horizon { break }

            // Free recharge over Δt in u = √(C/Cmax).
            let dt = next - tLast
            if dt > 0 {
                let u = (cap / capacity).squareRoot()
                let u2 = 1 - (1 - u) * exp(-5 * dt / tau)
                cap = capacity * u2 * u2
                if cap < minCapPre { minCapPre = cap }
            }
            tLast = next

            // Apply the event.
            let before = cap
            cap += states[idx].amount
            if cap > capacity { cap = capacity }
            observe?(next, before, cap)
            if cap <= 0 {
                return (true, next, 0)
            }
            if cap < minCap { minCap = cap }

            // Schedule the node's next activation, including the clip reload.
            states[idx].tNext += states[idx].cycleTime
            states[idx].shot += 1
            if states[idx].clipSize > 0 && states[idx].shot % states[idx].clipSize == 0 {
                states[idx].shot = 0
                states[idx].tNext += states[idx].reloadTime
            }
        }

        return (false, .infinity, minCap)
    }
}
