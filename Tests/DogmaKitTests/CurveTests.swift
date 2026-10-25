//
//  CurveTests.swift
//  DogmaKit
//
//  Curves for plotting: DPS by range and by target velocity, lock time by signature radius,
//  capacitor level by time. Each curve must agree point by point with the stat it samples.
//

import Foundation
import Testing
@testable import DogmaKit

@Suite("Curves", .setupDebugNames)
struct CurveTests {

    private static let hull = PilotID(1).hull

    private func rifter(_ modules: [TypeID], charge: TypeID? = nil) async throws -> DogmaEngine {
        let engine = DogmaEngine()
        try await engine.edit { fit in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: .rifter)
            for typeID in modules {
                let module = try hull.modules.add(typeID)
                if let charge, typeID == ._200mmAutoCannonII {
                    try module.setCharge(charge)
                }
            }
        }
        return engine
    }

    private func isClose(_ a: Double, _ b: Double, tolerance: Double = 1e-9) -> Bool {
        abs(a - b) <= tolerance * max(abs(a), abs(b), 1)
    }

    // MARK: - Sampling

    @Test("Sampling includes both ends exactly and spaces points evenly")
    func sampling() {
        let curve = Curve(sampling: 0...0.3, count: 4) { $0 * 2 }
        #expect(curve.points.map(\.x).first == 0)
        #expect(curve.points.map(\.x).last == 0.3)
        #expect(curve.points.count == 4)
        #expect(curve.points.allSatisfy { $0.y == $0.x * 2 })
        #expect(Curve(sampling: 5...5, count: 10) { $0 }.points.count == 1)
    }

    @Test("TargetProfile derives angular velocity from transversal speed")
    func targetProfile() {
        let profile = TargetProfile(signature: 40, velocity: 1000, angle: 30)
        #expect(isClose(profile.target(at: 10_000).angularVelocity, 0.05))
        #expect(profile.target(at: 0).angularVelocity == .infinity)
        #expect(TargetProfile(signature: 40, velocity: 1000, angle: 0).target(at: 5000).angularVelocity == 0)
    }

    // MARK: - DPS

    @Test("DPS by range matches dps at every point and falls off past optimal")
    func dpsByRange() async throws {
        let engine = try await rifter([._200mmAutoCannonII, ._200mmAutoCannonII], charge: .fusionS)
        // A stationary target: with transversal speed tracking improves with range, and DPS
        // past optimal is no longer monotonic.
        let profile = TargetProfile(signature: 125)
        let (curve, armament, optimal) = await engine.evaluate { stats in
            let hull = stats[Self.hull]
            let armament = hull.armament
            return (armament.dpsByRange(against: profile, over: 1000...30_000, samples: 30),
                    armament,
                    armament.entries.first?.weapon.optimal ?? 0)
        }

        #expect(curve.points.count == 30)
        for point in curve.points {
            #expect(point.y == armament.dps(to: profile.target(at: point.x)))
        }
        let totals = curve.map { $0.sum() }.points
        #expect(totals.contains { $0.y > 0 })
        let beyondOptimal = totals.filter { $0.x > optimal }
        #expect(!beyondOptimal.isEmpty)
        #expect(zip(beyondOptimal, beyondOptimal.dropFirst()).allSatisfy { $0.y >= $1.y })
    }

    @Test("DPS by velocity drops as the target speeds up")
    func dpsByVelocity() async throws {
        let engine = try await rifter([._200mmAutoCannonII], charge: .fusionS)
        let profile = TargetProfile(signature: 125)
        let curve = await engine.evaluate { stats in
            stats[Self.hull].armament.dpsByVelocity(against: profile, at: 2000, over: 0...3000, samples: 31)
        }
        let totals = curve.map { $0.sum() }.points.map(\.y)

        #expect(totals.first! > 0)
        #expect(zip(totals, totals.dropFirst()).allSatisfy { $0 >= $1 })
        #expect(totals.last! < totals.first!)
    }

    // MARK: - Lock time

    @Test("Lock time by signature matches lockTime and gets shorter for larger targets")
    func lockTimeBySignature() async throws {
        let engine = try await rifter([])
        let targeting = await engine.evaluate { $0[Self.hull].targeting }
        let curve = targeting.lockTimeBySignature(over: 10...1000, samples: 50)

        #expect(curve.points.allSatisfy { $0.y == targeting.lockTime(signatureRadius: $0.x) })
        let times = curve.points.map(\.y)
        #expect(zip(times, times.dropFirst()).allSatisfy { $0 >= $1 })
        #expect(times.last! < times.first!)
    }

    // MARK: - Capacitor

    @Test("An unstable capacitor curve runs dry when the simulation says it does")
    func unstableCapacitor() async throws {
        // A cruiser-size MWD on a frigate drains faster than the capacitor recharges.
        let engine = try await rifter([._50MNMicrowarpdriveII])
        let simulator = await engine.evaluate { $0[Self.hull].capacitorSimulator() }
        let result = simulator.run()
        try #require(result.lastsFor.isFinite, "nodes = \(simulator.nodes), result = \(result)")

        let curve = simulator.levelByTime(duration: result.lastsFor * 2)
        let last = try #require(curve.points.last)
        #expect(last.x == result.lastsFor)
        #expect(last.y == 0)
        #expect(curve.points.allSatisfy { (0...1).contains($0.y) })
        #expect(zip(curve.points, curve.points.dropFirst()).allSatisfy { $0.x <= $1.x })
    }

    @Test("A stable capacitor curve dips to the simulated minimum and never runs dry")
    func stableCapacitor() async throws {
        let engine = try await rifter([._1MNAfterburnerII])
        let simulator = await engine.evaluate { $0[Self.hull].capacitorSimulator() }
        let result = simulator.run()
        #expect(result.isStable)

        // The horizon `run()` uses for a stable fit.
        let horizon = min(max(simulator.rechargeTime * 6, 300), 6 * 3600)
        let curve = simulator.levelByTime(duration: horizon, step: 5)
        let minimum = curve.points.map(\.y).min()!

        #expect(isClose(minimum, result.minimumLevel))
        #expect(curve.points.last?.x == horizon)
        #expect(curve.points.allSatisfy { $0.y > 0 && $0.y <= 1 })
    }

    @Test("Without consumers the capacitor stays full")
    func idleCapacitor() async throws {
        let engine = try await rifter([])
        let simulator = await engine.evaluate { $0[Self.hull].capacitorSimulator() }
        let curve = simulator.levelByTime(duration: 60, step: 10)

        #expect(curve.points.allSatisfy { $0.y == 1 })
        #expect(curve.points.last?.x == 60)
    }
}
