//
//  HeatTests.swift
//  DogmaKit
//
//  Overheat tests.
//

import Foundation
import Testing
@testable import DogmaKit

// MARK: - Simulator as a pure value

@Suite("Overheat: simulator", .setupDebugNames)
struct HeatSimulatorTests {

    /// A rack of `count` slots, all filled with 40 HP modules and online.
    private static func rack(_ slot: Entity.Module.Slot,
                             count: Int,
                             attenuation: Double = 0.5,
                             capacity: Double = 1,
                             online: Int? = nil,
                             nodes: [HeatSimulator.Node] = []) -> HeatSimulator.Rack {
        let onlineCount = online ?? count
        let sockets = (0..<count).map {
            HeatSimulator.Socket(hitPoints: 40, isOnline: $0 < onlineCount)
        }
        return HeatSimulator.Rack(slot: slot,
                                  capacity: capacity,
                                  attenuation: attenuation,
                                  dissipationRate: 0.01,
                                  sockets: sockets,
                                  nodes: nodes)
    }

    /// 5MN Microwarpdrive II: 10 s cycle, absorbtion 0.04, heatDamage 19.
    private static func mwd(socket: Int = 0, damage: Double = 19) -> HeatSimulator.Node {
        HeatSimulator.Node(socket: socket, cycleTime: 10, absorbtionRate: 0.04, damage: damage)
    }

    /// Rifter: 3 hi / 3 med / 4 low / 3 rig, hgm 1.0. Med slot 0 is overheated.
    private static func rifter(nodes: [HeatSimulator.Node] = [HeatSimulatorTests.mwd()],
                               medOnline: Int? = nil) -> HeatSimulator {
        HeatSimulator(heatGenerationMultiplier: 1,
                      racks: [Self.rack(.hi, count: 3),
                              Self.rack(.med, count: 3, online: medOnline, nodes: nodes),
                              Self.rack(.low, count: 4)],
                      rigSlots: 3)
    }

    @Test("Reference scenario: the MWD burns itself out on the 5th cycle")
    func referenceBurnout() {
        let result = Self.rifter().run()

        // Fs = (3 + 3 + 4) online / (3 + 3 + 4 + 3) slots.
        #expect(abs(result.slotFactor - 10.0 / 13.0) < 1e-12)

        let source = result.modules.first { $0.slot == .med && $0.socket == 0 }
        #expect(source?.burnoutTime == 50)

        // Independent recomputation: damage is applied at the end of each cycle, probability = H(t)·Fs·attenuation^0.
        var expected = 0.0
        for cycle in 1...5 {
            let heat = 1 - exp(-0.04 * 10 * Double(cycle))
            expected += min(1, heat * 10.0 / 13.0) * 19
        }
        #expect(abs((source?.damageTaken ?? 0) - expected) < 1e-9)
        #expect(expected > 40, "the module must be dead: \(expected)")
    }

    @Test("The source dies first, neighbours later the farther they are")
    func attenuationOrdersNeighbours() {
        let result = Self.rifter().run()

        let near = result.modules.first { $0.slot == .med && $0.socket == 1 }!
        let far = result.modules.first { $0.slot == .med && $0.socket == 2 }!

        #expect(!near.isBurnedOut && !far.isBurnedOut, "neighbours must survive a single MWD")
        #expect(near.damageTaken > far.damageTaken)
        // Attenuation 0.5 per slot: half as much at each step.
        #expect(abs(near.damageTaken / far.damageTaken - 2) < 1e-9)

        // Racks without overheated modules take no damage.
        #expect(result.modules.filter { $0.slot != .med }.allSatisfy { $0.damageTaken == 0 })
    }

    @Test("Fs is global: rigs in the denominator, offline modules not in the numerator")
    func slotFactorIsGlobal() {
        let base = Self.rifter().run()

        // Same ship without rig slots: smaller denominator, higher Fs, burns faster.
        let noRigs = HeatSimulator(heatGenerationMultiplier: 1,
                                   racks: [Self.rack(.hi, count: 3),
                                           Self.rack(.med, count: 3, nodes: [Self.mwd()]),
                                           Self.rack(.low, count: 4)],
                                   rigSlots: 0).run()
        #expect(noRigs.slotFactor > base.slotFactor)
        #expect(noRigs.modules.first { $0.socket == 0 && $0.slot == .med }!.burnoutTime! <= base.modules.first { $0.socket == 0 && $0.slot == .med }!.burnoutTime!)

        // Two offline meds: smaller numerator, weaker damage, longer life. An offline module
        // still takes damage; it just does not count as an occupied slot for heating.
        let colder = Self.rifter(medOnline: 1).run()
        #expect(colder.slotFactor < base.slotFactor)
        let colderSource = colder.modules.first { $0.socket == 0 && $0.slot == .med }!
        #expect(colderSource.burnoutTime! > base.modules.first { $0.socket == 0 && $0.slot == .med }!.burnoutTime!)
        #expect(colder.modules.first { $0.socket == 1 && $0.slot == .med }!.damageTaken > 0)
    }

    @Test("A burned-out source stops heating the rack")
    func deadSourceStopsHeating() {
        let result = Self.rifter().run()
        let rack = result.rack(.med)!

        #expect(rack.segments.count == 2, "curve segments: before and after the MWD dies")
        #expect(rack.segments[0].start == 0)
        #expect(abs(rack.segments[0].generation - 0.04) < 1e-12)
        #expect(rack.segments[1].start == 50)
        #expect(rack.segments[1].generation == 0, "no sources left, the rack cools")

        // On the first segment the curve is exactly C·(1 − e^{−gt}).
        #expect(rack.heat(at: 0) == 0)
        #expect(abs(rack.heat(at: 25) - (1 - exp(-1))) < 1e-12, "H(1/g) = C·(1 − 1/e)")
        // Heat falls after the source dies.
        #expect(rack.heat(at: 200) < rack.heat(at: 50))
    }

    @Test("H(0) = 0 for any rack capacity")
    func heatStartsAtZero() {
        // A `C − e^{−gt}` form would give −1 here and negative damage.
        for capacity in [0.0, 0.5, 1.0, 1.5] {
            let sim = HeatSimulator(heatGenerationMultiplier: 1,
                                    racks: [Self.rack(.med, count: 3, capacity: capacity,
                                                      nodes: [Self.mwd()])],
                                    rigSlots: 3)
            let result = sim.run()
            let rack = result.rack(.med)!
            #expect(rack.heat(at: 0) == 0)
            #expect(rack.heat(at: 10) >= 0, "capacity \(capacity): heat cannot be negative")
            #expect(result.modules.allSatisfy { $0.damageTaken >= 0 })
        }
    }

    @Test("Degenerate inputs do not hang the simulator")
    func degenerateInputsTerminate() {
        // Zero attenuation: neighbours are invulnerable, but the source finishes itself off.
        let noAttenuation = HeatSimulator(
            heatGenerationMultiplier: 1,
            racks: [Self.rack(.med, count: 3, attenuation: 0, nodes: [Self.mwd()])],
            rigSlots: 3).run()
        #expect(noAttenuation.modules.first { $0.socket == 0 }!.isBurnedOut)
        #expect(noAttenuation.modules.first { $0.socket == 1 }!.damageTaken == 0)
        #expect(!noAttenuation.isTruncated)

        // Zero damage: nothing burns out, the simulation runs to the horizon.
        let noDamage = HeatSimulator(
            heatGenerationMultiplier: 1,
            racks: [Self.rack(.med, count: 3, nodes: [Self.mwd(damage: 0)])],
            rigSlots: 3).run(horizon: 100)
        #expect(noDamage.modules.allSatisfy { !$0.isBurnedOut })
        #expect(noDamage.isTruncated)

        // Zero cycle: the node is dropped.
        let zeroCycle = HeatSimulator(
            heatGenerationMultiplier: 1,
            racks: [Self.rack(.med, count: 3, nodes: [
                HeatSimulator.Node(socket: 0, cycleTime: 0, absorbtionRate: 0.04, damage: 19)])],
            rigSlots: 3).run()
        #expect(zeroCycle.modules.allSatisfy { $0.damageTaken == 0 })

        // No heat and no slots.
        #expect(HeatSimulator(heatGenerationMultiplier: 1, racks: [], rigSlots: 0).run().modules.isEmpty)
    }

    @Test("Clip reload spaces out the cycles")
    func clipDelaysCycles() {
        // Clip of 5 shots + 10 s reload: the sixth activation is at 70, not 60.
        let withClip = HeatSimulator(
            heatGenerationMultiplier: 1,
            racks: [Self.rack(.med, count: 3, nodes: [
                HeatSimulator.Node(socket: 0, cycleTime: 10, clipSize: 5, reloadTime: 10,
                                   absorbtionRate: 0.04, damage: 10)])],
            rigSlots: 3).run()

        let withoutClip = HeatSimulator(
            heatGenerationMultiplier: 1,
            racks: [Self.rack(.med, count: 3, nodes: [
                HeatSimulator.Node(socket: 0, cycleTime: 10, absorbtionRate: 0.04, damage: 10)])],
            rigSlots: 3).run()

        let a = withClip.modules.first { $0.socket == 0 }!.burnoutTime
        let b = withoutClip.modules.first { $0.socket == 0 }!.burnoutTime
        #expect(a != nil && b != nil)
        #expect(a! > b!, "with a reload the module lives longer: \(a!) vs \(b!)")
        #expect(a!.truncatingRemainder(dividingBy: 10) == 0)
    }

    @Test("Spread: burnout time estimates are ordered")
    func burnoutSpread() {
        let source = Self.rifter().run().modules.first { $0.slot == .med && $0.socket == 0 }!

        #expect(source.damageDeviation > 0)
        #expect(source.burnoutDeviation > 0)

        let early = source.timeToBurnout(probability: 0.05)!
        let median = source.timeToBurnout(probability: 0.5)!
        let late = source.timeToBurnout(probability: 0.95)!
        #expect(early < median && median < late)
        #expect(abs(median - source.burnoutTime!) < 1e-9, "median equals the expected time")
        // Symmetry of the normal approximation.
        #expect(abs((median - early) - (late - median)) < 1e-6)

        // The survival function is monotonic and consistent with the quantiles.
        #expect(source.survivalProbability(at: 0) > 0.99)
        #expect(abs(source.survivalProbability(at: median) - 0.5) < 1e-6)
        #expect(abs(source.survivalProbability(at: early) - 0.95) < 1e-6)
        #expect(source.survivalProbability(at: 1000) < 0.01)
    }

    @Test("Normal CDF and quantile are inverse to each other")
    func normalRoundTrip() {
        for p in [0.001, 0.05, 0.25, 0.5, 0.75, 0.95, 0.999] {
            let x = HeatSimulator.Result.normalQuantile(p)
            #expect(abs(HeatSimulator.Result.normalCDF(x) - p) < 1e-8, "p = \(p)")
        }
        #expect(abs(HeatSimulator.Result.normalCDF(0) - 0.5) < 1e-12)
        #expect(abs(HeatSimulator.Result.normalQuantile(0.975) - 1.959963985) < 1e-6)
    }
}

// MARK: - Built from a fit

@Suite("Overheat: built from a fit", .setupDebugNames)
struct HeatFitTests {

    private static let hull = PilotID(1).hull

    /// A fully fitted Rifter: 3 hi, 3 med, 4 low. Only the MWD is overheated.
    private static func rifter(skillLevel: UInt8 = 5) async throws -> (DogmaEngine, ModuleID) {
        let engine = DogmaEngine()
        let mwd = try await engine.edit { fit -> ModuleID in
            let pilot = try fit.pilots.add(skillLevel: skillLevel)
            let hull = pilot.hull
            try hull.set(typeID: .rifter)

            for _ in 0..<3 {
                let gun = try hull.modules.add(._200mmAutoCannonII)
                gun.state = .active
            }

            let mwd = try hull.modules.add(._5MNMicrowarpdriveII)
            mwd.state = .overloaded
            let mwdID = mwd.id
            let scram = try hull.modules.add(.warpScramblerII)
            scram.state = .active
            let web = try hull.modules.add(.stasisWebifierII)
            web.state = .active

            for _ in 0..<4 {
                let repairer = try hull.modules.add(.smallArmorRepairerII)
                repairer.state = .online
            }
            return mwdID
        }
        return (engine, mwd)
    }

    @Test("A rack built from a fit matches the manual calculation")
    func collectedFromFit() async throws {
        let (engine, mwdID) = try await Self.rifter()

        let (result, damage, socket, state) = await engine.evaluate { stats -> (HeatSimulator.Result, Double, Int, Entity.Module.State) in
            let hull = stats[Self.hull]
            let mwd = hull.modules[mwdID]
            return (hull.heat(), mwd.attributes[.heatDamage] ?? 0, mwd.socket, mwd.effectiveState)
        }

        #expect(state == .overloaded, "the module must be overheated, otherwise the test is meaningless")
        #expect(socket == 0)
        #expect(abs(result.slotFactor - 10.0 / 13.0) < 1e-12, "Fs = 10/13, not 3/3 over the med rack")

        let source = result[mwdID]
        #expect(source != nil)
        #expect(source?.slot == .med)
        #expect(source?.isBurnedOut == true)

        // Same recomputation as the reference test, with the real heatDamage (Thermodynamics included).
        var expected = 0.0
        var cycles = 0
        while expected < 40 {
            cycles += 1
            expected += min(1, (1 - exp(-0.04 * 10 * Double(cycles))) * 10.0 / 13.0) * damage
        }
        #expect(source?.burnoutTime == Double(cycles) * 10)
        #expect(abs((source?.damageTaken ?? 0) - expected) < 1e-6)
        // The MWD burns out first.
        #expect(result.firstBurnout?.id == mwdID)
    }

    @Test("Thermodynamics reduces damage and extends module life")
    func thermodynamicsExtendsLife() async throws {
        let (trained, mwdID) = try await Self.rifter(skillLevel: 5)
        let (untrained, _) = try await Self.rifter(skillLevel: 0)

        let (damage5, time5) = await trained.evaluate { stats -> (Double, Double?) in
            let hull = stats[Self.hull]
            return (hull.modules[mwdID].attributes[.heatDamage] ?? 0,
                    hull.heat()[mwdID]?.burnoutTime)
        }
        let (damage0, time0) = await untrained.evaluate { stats -> (Double, Double?) in
            let hull = stats[Self.hull]
            return (hull.modules[mwdID].attributes[.heatDamage] ?? 0,
                    hull.heat()[mwdID]?.burnoutTime)
        }

        #expect(abs(damage0 - 19) < 1e-9, "base heatDamage of 5MN MWD II: \(damage0)")
        #expect(abs(damage5 - 19 * 0.75) < 1e-9, "Thermodynamics V gives −25%: \(damage5)")
        #expect(time5! > time0!, "\(time5!) vs \(time0!)")
    }

    @Test("Nothing happens without overheated modules")
    func nothingOverheated() async throws {
        let (engine, mwdID) = try await Self.rifter()
        try await engine.edit { fit in
            fit[mwdID].state = .active
        }
        let result = await engine.evaluate { stats in stats[Self.hull].heat() }
        #expect(result.modules.allSatisfy { $0.damageTaken == 0 && !$0.isBurnedOut })
        #expect(result.duration == 0)
        #expect(!result.isTruncated)
    }

    @Test("Overheat does not depend on module insertion order")
    func orderIndependent() async throws {
        let (engine, mwdID) = try await Self.rifter()
        let direct = await engine.evaluate { stats in stats[Self.hull].heat()[mwdID]?.damageTaken ?? 0 }

        // Same fit, but med modules are added in reverse order and placed in the same sockets manually.
        let reversed = DogmaEngine()
        let reversedID = try await reversed.edit { fit -> ModuleID in
            let pilot = try fit.pilots.add(skillLevel: 5)
            let hull = pilot.hull
            try hull.set(typeID: .rifter)
            for _ in 0..<3 {
                let gun = try hull.modules.add(._200mmAutoCannonII)
                gun.state = .active
            }

            let web = try hull.modules.add(.stasisWebifierII)
            web.state = .active
            web.socket = 2
            let scram = try hull.modules.add(.warpScramblerII)
            scram.state = .active
            scram.socket = 1
            let mwd = try hull.modules.add(._5MNMicrowarpdriveII)
            mwd.state = .overloaded
            mwd.socket = 0

            for _ in 0..<4 {
                let repairer = try hull.modules.add(.smallArmorRepairerII)
                repairer.state = .online
            }
            return mwd.id
        }
        let swapped = await reversed.evaluate { stats in stats[Self.hull].heat()[reversedID]?.damageTaken ?? 0 }

        #expect(abs(direct - swapped) < 1e-12, "\(direct) vs \(swapped)")
    }
}
