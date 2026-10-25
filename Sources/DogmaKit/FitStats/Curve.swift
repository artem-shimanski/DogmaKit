//
//  Curve.swift
//  DogmaKit
//

import Foundation

/// A sampled function of one variable, ready for plotting: DPS by range or target velocity,
/// lock time by signature radius, capacitor level by time. Points are sorted by `x`.
///
/// Curves are built from the value types the engine exposes (`Armament`, `Targeting`,
/// `CapacitorSimulator`), so they work the same on `FitStats` and on detached snapshots.
public struct Curve<Value: Sendable & Hashable>: Sendable, Hashable {

    public struct Point: Sendable, Hashable {
        public var x: Double
        public var y: Value

        @inlinable
        public init(x: Double, y: Value) {
            self.x = x
            self.y = y
        }
    }

    public var points: [Point]

    @inlinable
    public init(points: [Point]) {
        self.points = points
    }

    /// Samples `function` at `count` evenly spaced points of `domain`, both ends included.
    /// A single-point domain or `count < 2` gives one point at the lower bound.
    public init(sampling domain: ClosedRange<Double>, count: Int, _ function: (Double) -> Value) {
        let count = max(1, count)
        let span = domain.upperBound - domain.lowerBound
        guard count > 1, span > 0 else {
            self.init(points: [Point(x: domain.lowerBound, y: function(domain.lowerBound))])
            return
        }
        let step = span / Double(count - 1)
        self.init(points: (0..<count).map { index in
            // The last point is the exact upper bound, not an accumulated sum.
            let x = index == count - 1 ? domain.upperBound : domain.lowerBound + Double(index) * step
            return Point(x: x, y: function(x))
        })
    }

    /// The same curve with a transformed value, e.g. a DPS vector reduced to its total.
    public func map<T>(_ transform: (Value) -> T) -> Curve<T> {
        Curve<T>(points: points.map { .init(x: $0.x, y: transform($0.y)) })
    }
}

/// A target described by its motion rather than by angular velocity, so a `Target` can be
/// derived at any range. The attacker is stationary; `angle` is between the target's
/// heading and the line of sight (90° is fully transversal, 0° flies straight in or out).
public struct TargetProfile: Sendable, Hashable {
    /// Signature radius, m.
    public var signature: Double
    /// Speed, m/s.
    public var velocity: Double
    /// Heading relative to the line of sight, degrees.
    public var angle: Double

    @inlinable
    public init(signature: Double, velocity: Double = 0, angle: Double = 90) {
        self.signature = signature
        self.velocity = velocity
        self.angle = angle
    }

    /// The target at `range`: angular velocity is `velocity · sin(angle) / range`, infinite
    /// at zero range for a target with transversal speed.
    public func target(at range: Double) -> Target {
        let transversal = abs(velocity * sin(angle * .pi / 180))
        let angularVelocity = range > 0 ? transversal / range : (transversal > 0 ? .infinity : 0)
        return Target(angularVelocity: angularVelocity, velocity: velocity, signature: signature, range: range)
    }
}

extension Armament {
    /// DPS against `target` placed at each range of `domain`, m.
    public func dpsByRange(from sources: FitStats.Hull.DamageSource = .all,
                           against target: TargetProfile,
                           over domain: ClosedRange<Double>,
                           samples: Int = 100) -> Curve<DamageVector> {
        Curve(sampling: domain, count: samples) { range in
            dps(from: sources, to: target.target(at: range))
        }
    }

    /// DPS against `target` at `range`, m, moving at each speed of `domain`, m/s.
    public func dpsByVelocity(from sources: FitStats.Hull.DamageSource = .all,
                              against target: TargetProfile,
                              at range: Double,
                              over domain: ClosedRange<Double>,
                              samples: Int = 100) -> Curve<DamageVector> {
        Curve(sampling: domain, count: samples) { velocity in
            var target = target
            target.velocity = velocity
            return dps(from: sources, to: target.target(at: range))
        }
    }
}

extension Targeting {
    /// Lock time, seconds, for each signature radius of `domain`, m.
    public func lockTimeBySignature(over domain: ClosedRange<Double>, samples: Int = 100) -> Curve<Double> {
        Curve(sampling: domain, count: samples) { lockTime(signatureRadius: $0) }
    }
}

extension CapacitorSimulator {
    /// Capacitor level (0…1) over `duration` seconds from a full capacitor, by the same
    /// event model as `run()`. `duration` must be finite: `Result.lastsFor` is infinite for a
    /// capacitor that does not run dry.
    ///
    /// Every activation gives two points at the same time, before and after it, so the
    /// curve keeps the exact sawtooth. Recharge between activations is sampled at most
    /// `step` seconds apart. The curve ends where the capacitor runs dry.
    public func levelByTime(duration: Double, step: Double = 1) -> Curve<Double> {
        precondition(duration.isFinite, "levelByTime needs a finite duration")
        guard capacity > 0, rechargeTime > 0, duration > 0 else {
            return Curve(points: [.init(x: 0, y: 1)])
        }
        let step = step > 0 ? step : duration
        var points: [Curve<Double>.Point] = [.init(x: 0, y: 1)]

        func recharge(from start: Double, level: Double, to end: Double) {
            var t = start + step
            while t < end {
                points.append(.init(x: t, y: rechargedLevel(level, over: t - start)))
                t += step
            }
        }

        var time = 0.0
        var level = 1.0
        let depleted = simulate(horizon: duration) { eventTime, before, after in
            recharge(from: time, level: level, to: eventTime)
            points.append(.init(x: eventTime, y: before / capacity))
            points.append(.init(x: eventTime, y: max(0, after) / capacity))
            time = eventTime
            level = max(0, after) / capacity
        }.depleted

        if !depleted {
            recharge(from: time, level: level, to: duration)
            if time < duration {
                points.append(.init(x: duration, y: rechargedLevel(level, over: duration - time)))
            }
        }
        return Curve(points: points)
    }

    /// Level after free recharge for `dt` seconds: `u = √level` relaxes to 1 as
    /// `1 − (1 − u)·exp(−5·dt/τ)`.
    func rechargedLevel(_ level: Double, over dt: Double) -> Double {
        let u = 1 - (1 - level.squareRoot()) * exp(-5 * dt / rechargeTime)
        return u * u
    }
}
