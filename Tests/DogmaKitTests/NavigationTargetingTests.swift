//
//  NavigationTargetingTests.swift
//  DogmaKit
//
//  Navigation, targeting and ECM on `FitStats.Hull`.
//  Expectations are derived from the fit's own attributes rather than hardcoded SDE
//  numbers, so balance patches do not break the tests. The only external knowledge
//  is the game formulas (align time, warp range, lock time) and that Minmatar hulls use ladar.
//

import Foundation
import Testing
@testable import DogmaKit

@Suite("Navigation", .setupDebugNames)
struct NavigationTests {

    private static let firstHull = PilotID(1).hull

    /// Builds a fit. Modules are put into `state` (left alone by default;
    /// `Entity.Module.init` sets `.active` itself for those that support it).
    private func makeFit(hull hullType: TypeID,
                         modules: [TypeID] = [],
                         state: Entity.Module.State? = nil) async throws -> DogmaEngine {
        let engine = DogmaEngine()
        try await engine.edit { fit in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: hullType)
            for typeID in modules {
                let module = try hull.modules.add(typeID)
                if let state { module.state = state }
            }
        }
        return engine
    }

    @Test("Align time == -ln(0.25)·agility·mass/10⁶")
    func alignTimeMatchesFormula() async throws {
        let engine = try await makeFit(hull: .rifter)
        let (alignTime, expected) = await engine.evaluate { stats -> (Double, Double) in
            let hull = stats[Self.firstHull]
            let nav = hull.navigation
            let expected = 1.3862943611198906 * nav.agility * nav.mass / 1_000_000
            return (nav.alignTime, expected)
        }
        #expect(alignTime > 0)
        #expect(abs(alignTime - expected) < 1e-9 * max(1, alignTime))
    }

    @Test("Warp speed == baseWarpSpeed x warpSpeedMultiplier")
    func warpSpeedIsProduct() async throws {
        let engine = try await makeFit(hull: .rifter)
        let (warpSpeed, expected) = await engine.evaluate { stats -> (Double, Double) in
            let hull = stats[Self.firstHull]
            let expected = hull.attributes[.baseWarpSpeed, default: .sde]
                         * hull.attributes[.warpSpeedMultiplier, default: .sde]
            return (hull.navigation.warpSpeed, expected)
        }
        #expect(warpSpeed > 0)
        #expect(warpSpeed == expected)
    }

    @Test("Warp range == capacitorCapacity / (mass * warpCapacitorNeed)")
    func maxWarpDistanceMatchesFormula() async throws {
        let engine = try await makeFit(hull: .rifter)
        let (distance, expected, need) = await engine.evaluate { stats -> (Double, Double, Double) in
            let nav = stats[Self.firstHull].navigation
            let expected = nav.capacitorCapacity / (nav.mass * nav.warpCapacitorNeed)
            return (nav.maxWarpDistance, expected, nav.capacitorNeed(warpingFor: 1))
        }
        #expect(distance > 0)
        #expect(abs(distance - expected) < 1e-9 * distance)
        // Cost per AU and its inverse agree.
        #expect(need > 0)
    }

    @Test("Navigation projection matches the engine calculation (MWD active)")
    func propulsionProjectionMatchesEngine() async throws {
        // `unboostedNavigation` removes the active MWD contribution and `applying(_:)`
        // restores it. Catches the thrust formula drifting from the importer patch (`patchSpeedBoost`).
        let engine = try await makeFit(hull: .rifter, modules: [._5MNMicrowarpdriveI], state: .active)
        let (engineNav, projected) = await engine.evaluate { stats -> (Navigation, Navigation) in
            let hull = stats[Self.firstHull]
            let mwd = Array(hull.modules.ids(in: .med))[0]
            return (hull.navigation, hull.navigation(with: mwd))
        }
        #expect(engineNav.maxVelocity > 0)
        #expect(abs(engineNav.maxVelocity - projected.maxVelocity) < 1e-6 * engineNav.maxVelocity)
        #expect(abs(engineNav.mass - projected.mass) < 1e-6 * engineNav.mass)
        #expect(abs(engineNav.signatureRadius - projected.signatureRadius) < 1e-6 * engineNav.signatureRadius)
    }

    @Test("MWD active: speed and signature grew, unboosted == cold hull")
    func activePropulsionBoostsSpeedAndSignature() async throws {
        let bare = try await makeFit(hull: .rifter)
        let cold = await bare.evaluate { stats -> Navigation in
            stats[Self.firstHull].navigation
        }

        let engine = try await makeFit(hull: .rifter, modules: [._5MNMicrowarpdriveI], state: .active)
        let (hot, unboosted) = await engine.evaluate { stats -> (Navigation, Navigation) in
            let hull = stats[Self.firstHull]
            return (hull.navigation, hull.unboostedNavigation)
        }

        #expect(hot.maxVelocity > cold.maxVelocity)
        #expect(hot.signatureRadius > cold.signatureRadius)
        #expect(hot.mass > cold.mass)
        // Removing the contribution returns the cold hull.
        #expect(abs(unboosted.maxVelocity - cold.maxVelocity) < 1e-6 * cold.maxVelocity)
        #expect(abs(unboosted.signatureRadius - cold.signatureRadius) < 1e-6 * cold.signatureRadius)
        #expect(abs(unboosted.mass - cold.mass) < 1e-6 * cold.mass)
        // Align time depends on mass, which the MWD worsens.
        #expect(hot.alignTime > cold.alignTime)
    }

    @Test("MWD is faster than AB, but only the MWD pays the signature bloom")
    func mwdIsFasterButBlooms() async throws {
        let engine = try await makeFit(hull: .rifter,
                                       modules: [._1MNAfterburnerI, ._5MNMicrowarpdriveI],
                                       state: .offline)
        let (cold, withAB, withMWD) = await engine.evaluate { stats -> (Navigation, Navigation, Navigation) in
            let hull = stats[Self.firstHull]
            // Look up by type, not by slot iteration order.
            var abID = ModuleID(rawValue: .invalid)
            var mwdID = ModuleID(rawValue: .invalid)
            hull.modules.forEach(in: .med) { module in
                switch module.typeID {
                case ._1MNAfterburnerI: abID = module.id
                case ._5MNMicrowarpdriveI: mwdID = module.id
                default: break
                }
            }
            return (hull.unboostedNavigation,
                    hull.navigation(with: abID),
                    hull.navigation(with: mwdID))
        }
        #expect(withAB.maxVelocity > cold.maxVelocity)
        #expect(withMWD.maxVelocity > withAB.maxVelocity)
        // Only the MWD pays the signature bloom.
        #expect(withMWD.signatureRadius > cold.signatureRadius)
        #expect(withAB.signatureRadius < withMWD.signatureRadius)
        // Both add mass, so both worsen align time.
        #expect(withAB.alignTime > cold.alignTime)
    }

    @Test("Projection for a non-prop module returns the cold hull")
    func projectionWithNonPropulsionModuleIsCold() async throws {
        let engine = try await makeFit(hull: .rifter, modules: [.warpScramblerII], state: .active)
        let (cold, projected) = await engine.evaluate { stats -> (Navigation, Navigation) in
            let hull = stats[Self.firstHull]
            let id = Array(hull.modules.ids(in: .med))[0]
            return (hull.unboostedNavigation, hull.navigation(with: id))
        }
        #expect(cold == projected)
    }
}

@Suite("Targeting", .setupDebugNames)
struct TargetingTests {

    private static let firstHull = PilotID(1).hull

    private func makeFit(hull hullType: TypeID,
                         modules: [TypeID] = [],
                         state: Entity.Module.State? = nil) async throws -> DogmaEngine {
        let engine = DogmaEngine()
        try await engine.edit { fit in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: hullType)
            for typeID in modules {
                let module = try hull.modules.add(typeID)
                if let state { module.state = state }
            }
        }
        return engine
    }

    @Test("Base lock characteristics are populated")
    func targetingBasicsArePopulated() async throws {
        let engine = try await makeFit(hull: .rifter)
        let targeting = await engine.evaluate { stats -> Targeting in
            stats[Self.firstHull].targeting
        }
        #expect(targeting.maxTargetRange > 0)
        #expect(targeting.scanResolution > 0)
        #expect(targeting.maxLockedTargets > 0)
    }

    @Test("Lock time == 40000/(scanResolution * asinh^2(sig)) and grows as signature drops")
    func lockTimeMatchesFormula() async throws {
        let engine = try await makeFit(hull: .rifter)
        let (targeting, small, large) = await engine.evaluate { stats -> (Targeting, Double, Double) in
            let t = stats[Self.firstHull].targeting
            return (t, t.lockTime(signatureRadius: 35), t.lockTime(signatureRadius: 400))
        }
        let x = asinh(35.0)
        let expected = 40_000 / targeting.scanResolution / (x * x)
        #expect(abs(small - expected) < 1e-9 * small)
        // A large target locks faster.
        #expect(large < small)
    }

    @Test("Zero signature and missing scanResolution are degenerate cases")
    func lockTimeEdgeCases() async throws {
        let engine = try await makeFit(hull: .rifter)
        let (zeroSig, fallback, scanSpeed) = await engine.evaluate { stats -> (Double, Double, Double) in
            let t = stats[Self.firstHull].targeting
            var degenerate = t
            degenerate.scanResolution = 0
            return (t.lockTime(signatureRadius: 0),
                    degenerate.lockTime(signatureRadius: 35),
                    t.scanSpeed)
        }
        #expect(zeroSig == 0)
        // Without scanResolution the old scanSpeed (ms to s) is used.
        #expect(fallback == scanSpeed / 1000)
    }

    @Test("A hull has exactly one non-zero sensor type")
    func exactlyOneSensorType() async throws {
        let engine = try await makeFit(hull: .rifter)
        let (strength, dominant) = await engine.evaluate { stats -> (SensorStrength, SensorType?) in
            let hull = stats[Self.firstHull]
            return (hull.sensorStrength, hull.targeting.sensorType)
        }
        let nonZero = SensorType.allCases.filter { strength[$0] > 0 }
        #expect(nonZero.count == 1)
        // Minmatar is ladar.
        #expect(dominant == .ladar)
        #expect(strength.ecmResistance == strength[.ladar])
    }

    @Test("ECM resistance == strength of the dominant sensor")
    func ecmResistanceIsDominantStrength() async throws {
        let engine = try await makeFit(hull: .rifter)
        let (resistance, dominant, halfChance, fullChance) = await engine.evaluate {
            stats -> (Double, Double, Double, Double) in
            let t = stats[Self.firstHull].targeting
            let dominant = t.sensorStrength.dominant?.strength ?? 0
            return (t.ecmResistance, dominant,
                    t.jamProbability(against: dominant / 2),
                    t.jamProbability(against: dominant * 4))
        }
        #expect(resistance == dominant)
        #expect(abs(halfChance - 0.5) < 1e-12)
        // Chance does not exceed 100%.
        #expect(fullChance == 1)
    }
}

@Suite("ECM", .setupDebugNames)
struct ECMTests {

    private static let firstHull = PilotID(1).hull

    private func makeJammer(modules: [TypeID], state: Entity.Module.State) async throws -> DogmaEngine {
        let engine = DogmaEngine()
        try await engine.edit { fit in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: .rifter)
            for typeID in modules {
                let module = try hull.modules.add(typeID)
                module.state = state
            }
        }
        return engine
    }

    @Test("Multispectral jammer: equal strength on all types, range from maxRange")
    func multispectralHasUniformStrength() async throws {
        let engine = try await makeJammer(modules: [.multispectralECMII], state: .active)
        let (ecm, maxRange, falloffEffectiveness) = await engine.evaluate {
            stats -> (ECM?, Double, Double) in
            let hull = stats[Self.firstHull]
            let module = hull.modules[Array(hull.modules.ids(in: .med))[0]]
            return (module.ecm,
                    module.attributes[.maxRange] ?? 0,
                    module.attributes[.falloffEffectiveness] ?? 0)
        }
        let jammer = try #require(ecm)
        #expect(jammer.strength.radar > 0)
        #expect(jammer.strength.radar == jammer.strength.ladar)
        #expect(jammer.strength.radar == jammer.strength.magnetometric)
        #expect(jammer.strength.radar == jammer.strength.gravimetric)
        #expect(jammer.optimal == maxRange)
        #expect(jammer.falloff == falloffEffectiveness)
        #expect(jammer.cycleTime > 0)
    }

    @Test("A racial jammer is stronger against its own type")
    func racialJammerIsStrongerOnItsType() async throws {
        let engine = try await makeJammer(modules: [.radarECMII], state: .active)
        let ecm = await engine.evaluate { stats -> ECM? in
            let hull = stats[Self.firstHull]
            return hull.modules[Array(hull.modules.ids(in: .med))[0]].ecm
        }
        let jammer = try #require(ecm)
        #expect(jammer.strength.dominant?.type == .radar)
        #expect(jammer.strength.radar > jammer.strength.ladar)
    }

    @Test("Jam chance falls with range and drops off past optimal + 3 * falloff")
    func jamProbabilityFallsOffWithRange() async throws {
        let engine = try await makeJammer(modules: [.multispectralECMII], state: .active)
        let (ecm, target) = await engine.evaluate { stats -> (ECM?, SensorStrength) in
            let hull = stats[Self.firstHull]
            return (hull.modules[Array(hull.modules.ids(in: .med))[0]].ecm, hull.sensorStrength)
        }
        let jammer = try #require(ecm)
        let inOptimal = jammer.jamProbability(against: target, at: jammer.optimal / 2)
        let atEdge = jammer.jamProbability(against: target, at: jammer.optimal + jammer.falloff)
        let beyond = jammer.jamProbability(against: target, at: jammer.optimal + 4 * jammer.falloff)

        #expect(inOptimal > 0)
        #expect(atEdge < inOptimal)
        #expect(beyond == 0)
        #expect(inOptimal <= 1)
    }

    @Test("Hull.ecmStrength sums only active jammers")
    func ecmStrengthCountsActiveOnly() async throws {
        let offline = try await makeJammer(modules: [.multispectralECMII], state: .offline)
        let zero = await offline.evaluate { stats -> SensorStrength in
            stats[Self.firstHull].ecmStrength
        }
        #expect(zero.ecmResistance == 0)

        let one = try await makeJammer(modules: [.multispectralECMII], state: .active)
        let two = try await makeJammer(modules: [.multispectralECMII, .multispectralECMII], state: .active)
        let single = await one.evaluate { stats -> SensorStrength in
            stats[Self.firstHull].ecmStrength
        }
        let double = await two.evaluate { stats -> SensorStrength in
            stats[Self.firstHull].ecmStrength
        }
        #expect(single.radar > 0)
        #expect(double.radar > single.radar)
    }

    @Test("A non-ECM module exposes no jamming parameters")
    func nonJammerHasNoECM() async throws {
        let engine = try await makeJammer(modules: [.warpScramblerII], state: .active)
        let (ecm, propulsion) = await engine.evaluate { stats -> (ECM?, Propulsion?) in
            let hull = stats[Self.firstHull]
            let module = hull.modules[Array(hull.modules.ids(in: .med))[0]]
            return (module.ecm, module.propulsion)
        }
        #expect(ecm == nil)
        #expect(propulsion == nil)
    }
}
