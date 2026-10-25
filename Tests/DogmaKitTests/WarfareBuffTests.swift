//
//  WarfareBuffTests.swift
//  DogmaKit
//
//  Warfare buff tests: Command Bursts (module + charge) and the Phenomena Generator.
//
//  A buff applies as `1 + warfareBuff{N}Value / 100` of the strength the engine computed on
//  the carrier. The buff ID lives on the charge, and bonuses exist only while the module is
//  active. The .gang domain reaches every hull in the session. Identical buffs do not stack
//  (the strongest wins); different buffs on one attribute multiply without a stacking penalty.
//  Expectations are derived from engine-computed values; two tests pin absolute SDE numbers
//  and may need updating after a rebalance.
//

import Testing
@testable import DogmaKit

@Suite("Warfare buffs", .setupDebugNames)
struct WarfareBuffTests {

    /// One pilot in the fleet.
    struct Booster: Sendable {
        var hull: TypeID = .claymore
        var burst: TypeID? = nil
        var charge: TypeID? = nil
        var state: Entity.Module.State = .active
        var skillLevel: UInt8 = 5

        /// A ship without a buff source.
        static func plain(hull: TypeID = .claymore, skillLevel: UInt8 = 5) -> Booster {
            Booster(hull: hull, skillLevel: skillLevel)
        }

        /// Shield Command Burst II with a charge (nil means no charge).
        static func shieldBurst(_ charge: TypeID?,
                                state: Entity.Module.State = .active,
                                skillLevel: UInt8 = 5) -> Booster {
            Booster(burst: .shieldCommandBurstII, charge: charge, state: state, skillLevel: skillLevel)
        }

        /// Avatar + Amarr Phenomena Generator: a source with its own warfareBuffNID.
        static func phenomenaGenerator(skillLevel: UInt8 = 5) -> Booster {
            Booster(hull: .avatar, burst: .amarrPhenomenaGenerator, skillLevel: skillLevel)
        }
    }

    private static func hullID(_ pilotIndex: UInt8) -> HullID {
        PilotID(pilotIndex).hull
    }

    /// Builds the fleet; returns the engine and each pilot's burst module id (nil if none).
    private func makeFleet(_ boosters: [Booster]) async throws -> (engine: DogmaEngine, bursts: [ModuleID?]) {
        let engine = DogmaEngine()
        let bursts: [ModuleID?] = try await engine.edit { fit -> [ModuleID?] in
            var result: [ModuleID?] = []
            for booster in boosters {
                let pilot = try fit.pilots.add(skillLevel: booster.skillLevel)
                let hull = pilot.hull
                try hull.set(typeID: booster.hull)

                guard let burstTypeID = booster.burst else {
                    result.append(nil)
                    continue
                }
                let burst = try hull.modules.add(burstTypeID)
                if let charge = booster.charge {
                    try burst.setCharge(charge)
                }
                burst.state = booster.state
                result.append(burst.id)
            }
            return result
        }
        return (engine, bursts)
    }

    private func hullAttribute(_ engine: DogmaEngine,
                               _ attribute: AttributeID,
                               on hull: HullID) async -> Double {
        await engine.evaluate { stats in
            stats[hull].attributes[attribute, default: .sde]
        }
    }

    /// Buff strength in percent as computed on the carrier.
    private func buffStrength(_ engine: DogmaEngine,
                              burst: ModuleID,
                              slot: AttributeID = .warfareBuff1Value) async -> Double {
        await engine.evaluate { stats in
            let hull = stats[burst.hull]
            let module = hull.modules[burst]
            return module.attributes[slot, default: .sde]
        }
    }

    private func effectiveStates(_ engine: DogmaEngine, _ bursts: [ModuleID?]) async -> [Entity.Module.State] {
        await engine.evaluate { stats in
            bursts.compactMap { $0 }.map { id in
                let hull = stats[id.hull]
                let module = hull.modules[id]
                return module.effectiveState
            }
        }
    }

    private func isClose(_ actual: Double, _ expected: Double, relative tolerance: Double = 1e-9) -> Bool {
        abs(actual - expected) <= tolerance * max(abs(expected), 1)
    }

    // MARK: - Buff ID from the charge, strength from the module

    @Test("A buff applies to the carrier as 1 + warfareBuff1Value / 100")
    func buffAppliesToOwnHull() async throws {
        let reference = try await makeFleet([.plain()])
        let base = await hullAttribute(reference.engine, .shieldCapacity, on: Self.hullID(1))

        let fleet = try await makeFleet([.shieldBurst(.shieldExtensionCharge)])
        let actual = await hullAttribute(fleet.engine, .shieldCapacity, on: Self.hullID(1))
        let strength = await buffStrength(fleet.engine, burst: fleet.bursts[0]!)

        #expect(base > 0)
        #expect(strength > 0, "Shield Extension Charge gives a positive shieldCapacity bonus")
        #expect(actual > base, "the buff must increase shieldCapacity")
        #expect(isClose(actual, base * (1 + strength / 100)),
                "actual = \(actual), expected = \(base * (1 + strength / 100))")
    }

    @Test("Strength is module base times charge multiplier times skill bonus")
    func buffStrengthComposition() async throws {
        let fleet = try await makeFleet([.shieldBurst(.shieldExtensionCharge, skillLevel: 5)])
        let strength = await buffStrength(fleet.engine, burst: fleet.bursts[0]!)

        #expect(isClose(strength, 17.25, relative: 1e-6), "strength = \(strength)")
    }

    @Test("Buff strength scales with skill level")
    func buffStrengthScalesWithSkillLevel() async throws {
        let trained = try await makeFleet([.shieldBurst(.shieldExtensionCharge, skillLevel: 5)])
        let rookie = try await makeFleet([.shieldBurst(.shieldExtensionCharge, skillLevel: 1)])

        let strong = await buffStrength(trained.engine, burst: trained.bursts[0]!)
        let weak = await buffStrength(rookie.engine, burst: rookie.bursts[0]!)

        #expect(strong > weak, "strong = \(strong), weak = \(weak)")
    }

    @Test("Without a charge the burst grants nothing: the buff ID is on the charge")
    func noChargeNoBuff() async throws {
        let reference = try await makeFleet([.plain()])
        let base = await hullAttribute(reference.engine, .shieldCapacity, on: Self.hullID(1))

        let fleet = try await makeFleet([.shieldBurst(nil)])
        let actual = await hullAttribute(fleet.engine, .shieldCapacity, on: Self.hullID(1))
        let strength = await buffStrength(fleet.engine, burst: fleet.bursts[0]!)

        #expect(isClose(actual, base), "actual = \(actual), base = \(base)")
        // The charge multiplier is not applied; the module keeps its own base.
        #expect(strength > 0 && strength < 3, "strength = \(strength)")
    }

    // MARK: - State gate

    @Test("The buff is not granted until the module is active")
    func buffRequiresActiveState() async throws {
        let reference = try await makeFleet([.plain()])
        let base = await hullAttribute(reference.engine, .shieldCapacity, on: Self.hullID(1))

        for state in [Entity.Module.State.offline, .online] {
            let fleet = try await makeFleet([.shieldBurst(.shieldExtensionCharge, state: state)])
            let actual = await hullAttribute(fleet.engine, .shieldCapacity, on: Self.hullID(1))
            #expect(isClose(actual, base), "state = \(state): actual = \(actual), base = \(base)")
        }

        let active = try await makeFleet([.shieldBurst(.shieldExtensionCharge, state: .active)])
        let actual = await hullAttribute(active.engine, .shieldCapacity, on: Self.hullID(1))
        #expect(actual > base)
    }

    // MARK: - .gang domain

    @Test("The buff reaches every hull in the fleet, not just its own")
    func buffAppliesToWholeFleet() async throws {
        let reference = try await makeFleet([.plain(), .plain()])
        let base = await hullAttribute(reference.engine, .shieldCapacity, on: Self.hullID(2))

        let fleet = try await makeFleet([.shieldBurst(.shieldExtensionCharge), .plain()])
        let actual = await hullAttribute(fleet.engine, .shieldCapacity, on: Self.hullID(2))
        let strength = await buffStrength(fleet.engine, burst: fleet.bursts[0]!)

        #expect(base > 0)
        #expect(isClose(actual, base * (1 + strength / 100)),
                "second hull: actual = \(actual), expected = \(base * (1 + strength / 100))")
    }

    // MARK: - Aggregating identical buffs

    @Test("Two boosters with the same buff do not stack")
    func sameBuffDoesNotStack() async throws {
        let reference = try await makeFleet([.plain(), .plain(), .plain()])
        let base = await hullAttribute(reference.engine, .shieldCapacity, on: Self.hullID(3))

        let single = try await makeFleet([.shieldBurst(.shieldExtensionCharge), .plain(), .plain()])
        let double = try await makeFleet([.shieldBurst(.shieldExtensionCharge),
                                          .shieldBurst(.shieldExtensionCharge),
                                          .plain()])

        // maxGroupActive = 1 is counted per hull, so both bursts are really active.
        let states = await effectiveStates(double.engine, double.bursts)
        #expect(states.count == 2)
        #expect(states.allSatisfy { $0 == .active }, "states = \(states)")

        // Read on the third hull, which grants nothing itself.
        let one = await hullAttribute(single.engine, .shieldCapacity, on: Self.hullID(3))
        let two = await hullAttribute(double.engine, .shieldCapacity, on: Self.hullID(3))

        #expect(one > base, "one booster must give a bonus")
        #expect(isClose(one, two), "identical buffs stacked: one = \(one), two = \(two)")
    }

    @Test("aggregateMode Maximum: the strongest of identical buffs applies")
    func strongestWinsForMaximumBuff() async throws {
        let reference = try await makeFleet([.plain(), .plain(), .plain()])
        let base = await hullAttribute(reference.engine, .shieldCapacity, on: Self.hullID(3))

        // Shield Extension (buff 12) is Maximum; strength differs by skill level.
        let fleet = try await makeFleet([.shieldBurst(.shieldExtensionCharge, skillLevel: 5),
                                         .shieldBurst(.shieldExtensionCharge, skillLevel: 1),
                                         .plain()])
        let strong = await buffStrength(fleet.engine, burst: fleet.bursts[0]!)
        let weak = await buffStrength(fleet.engine, burst: fleet.bursts[1]!)
        #expect(strong > weak, "strong = \(strong), weak = \(weak)")

        let actual = await hullAttribute(fleet.engine, .shieldCapacity, on: Self.hullID(3))
        #expect(isClose(actual, base * (1 + strong / 100)),
                "the strongest must win: actual = \(actual), expected = \(base * (1 + strong / 100))")
        #expect(!isClose(actual, base * (1 + weak / 100)))
    }

    @Test("aggregateMode Minimum: the strongest (smallest) multiplier applies")
    func strongestWinsForMinimumBuff() async throws {
        let reference = try await makeFleet([.plain(), .plain(), .plain()])
        let base = await hullAttribute(reference.engine, .shieldEmDamageResonance, on: Self.hullID(3))

        // Shield Harmonizing (buff 10) is Minimum with a negative value (lowers resonance).
        let fleet = try await makeFleet([.shieldBurst(.shieldHarmonizingCharge, skillLevel: 5),
                                         .shieldBurst(.shieldHarmonizingCharge, skillLevel: 1),
                                         .plain()])
        let strong = await buffStrength(fleet.engine, burst: fleet.bursts[0]!)
        let weak = await buffStrength(fleet.engine, burst: fleet.bursts[1]!)
        #expect(strong < 0 && weak < 0, "strong = \(strong), weak = \(weak)")
        #expect(strong < weak, "skill V must give a stronger (more negative) buff")

        let actual = await hullAttribute(fleet.engine, .shieldEmDamageResonance, on: Self.hullID(3))
        #expect(base > 0)
        #expect(actual < base, "resonance must drop")
        #expect(isClose(actual, base * (1 + strong / 100)),
                "actual = \(actual), expected = \(base * (1 + strong / 100))")
    }

    // MARK: - Different buffs together

    @Test("Different buffs on one attribute multiply without a stacking penalty")
    func differentBuffsMultiplyWithoutStackingPenalty() async throws {
        let reference = try await makeFleet([.plain(), .plain(hull: .avatar), .plain()])
        let base = await hullAttribute(reference.engine, .shieldEmDamageResonance, on: Self.hullID(3))

        // Buff 10 (Shield Harmonizing, Minimum, negative) and buff 41 (Amarr Phenomena
        // Generator, slot 3, Maximum, positive) both target shieldEmDamageResonance.
        let fleet = try await makeFleet([.shieldBurst(.shieldHarmonizingCharge),
                                         .phenomenaGenerator(),
                                         .plain()])
        let burstStrength = await buffStrength(fleet.engine, burst: fleet.bursts[0]!)
        let generatorStrength = await buffStrength(fleet.engine, burst: fleet.bursts[1]!,
                                                   slot: .warfareBuff3Value)
        #expect(burstStrength < 0, "burstStrength = \(burstStrength)")
        #expect(generatorStrength > 0, "generatorStrength = \(generatorStrength)")

        let actual = await hullAttribute(fleet.engine, .shieldEmDamageResonance, on: Self.hullID(3))
        let expected = base * (1 + burstStrength / 100) * (1 + generatorStrength / 100)
        // A stacking penalty would have weakened the second multiplier.
        #expect(isClose(actual, expected), "actual = \(actual), expected = \(expected)")
    }

    @Test("The Phenomena Generator grants a buff without a charge")
    func phenomenaGeneratorNeedsNoCharge() async throws {
        let reference = try await makeFleet([.plain(hull: .avatar)])
        let base = await hullAttribute(reference.engine, .rechargeRate, on: Self.hullID(1))

        let fleet = try await makeFleet([.phenomenaGenerator()])
        let actual = await hullAttribute(fleet.engine, .rechargeRate, on: Self.hullID(1))
        let strength = await buffStrength(fleet.engine, burst: fleet.bursts[0]!)

        #expect(base > 0)
        #expect(actual < base, "buff 39 lowers rechargeRate")
        #expect(isClose(actual, base * (1 + strength / 100)),
                "actual = \(actual), expected = \(base * (1 + strength / 100))")

        // Pinned SDE value: the generator's warfareBuff1Value is -30 and nothing modifies it
        // (the modifiers are gated by *Command skills, which the generator does not require).
        #expect(isClose(strength, -30, relative: 1e-6), "strength = \(strength)")
    }

    // MARK: - Read API

    private func hullBuffs(_ engine: DogmaEngine, on hull: HullID) async -> [FitStats.WarfareBuff] {
        await engine.evaluate { stats in stats[hull].warfareBuffs }
    }

    @Test("Hull.warfareBuffs lists the applied buffs with their source and value")
    func hullListsAppliedBuffs() async throws {
        let fleet = try await makeFleet([.shieldBurst(.shieldExtensionCharge), .plain()])
        let burst = fleet.bursts[0]!
        let strength = await buffStrength(fleet.engine, burst: burst)

        for hull in [Self.hullID(1), Self.hullID(2)] {
            let buffs = await hullBuffs(fleet.engine, on: hull)
            let buff = try #require(buffs.first { $0.id == 12 }, "buffs = \(buffs.map(\.id))")
            #expect(isClose(buff.value, strength), "value = \(buff.value), strength = \(strength)")
            #expect(buff.operation == .postPercent)
            #expect(buff.aggregateMode == .maximum)
            #expect(buff.sources.map(\.entityID) == [burst.rawValue])
            #expect(buff.sources.first?.typeID == .shieldCommandBurstII)
        }
    }

    @Test("An inactive burst applies nothing but still reports what it broadcasts")
    func inactiveBurstAppliesNothing() async throws {
        let fleet = try await makeFleet([.shieldBurst(.shieldExtensionCharge, state: .online)])
        let burst = fleet.bursts[0]!

        let applied = await hullBuffs(fleet.engine, on: Self.hullID(1))
        let broadcast = await fleet.engine.evaluate { stats in
            stats[burst].warfareBuffs
        }

        #expect(applied.isEmpty, "applied = \(applied.map(\.id))")
        #expect(broadcast.contains { $0.id == 12 }, "broadcast = \(broadcast.map(\.id))")
    }

    @Test("A burst without a charge broadcasts nothing")
    func burstWithoutChargeBroadcastsNothing() async throws {
        let fleet = try await makeFleet([.shieldBurst(nil)])
        let burst = fleet.bursts[0]!
        let broadcast = await fleet.engine.evaluate { stats in
            stats[burst].warfareBuffs
        }
        #expect(broadcast.isEmpty)
    }

    @Test("Identical buffs from several boosters: the strongest source is first and sets the value",
          arguments: [TypeID.shieldExtensionCharge, .shieldHarmonizingCharge])
    func strongestSourceFirst(charge: TypeID) async throws {
        let fleet = try await makeFleet([.shieldBurst(charge, skillLevel: 1),
                                         .shieldBurst(charge, skillLevel: 5),
                                         .plain()])
        let weak = await buffStrength(fleet.engine, burst: fleet.bursts[0]!)
        let strong = await buffStrength(fleet.engine, burst: fleet.bursts[1]!)

        let buffs = await hullBuffs(fleet.engine, on: Self.hullID(3))
        let broadcast = await fleet.engine.evaluate { [burst = fleet.bursts[1]!] stats in
            stats[burst].warfareBuffs
        }
        let id = try #require(broadcast.first?.id)
        let buff = try #require(buffs.first { $0.id == id })

        #expect(buff.sources.map(\.entityID) == [fleet.bursts[1]!.rawValue, fleet.bursts[0]!.rawValue])
        #expect(buff.sources.map(\.value) == [strong, weak])
        #expect(buff.value == strong)
    }

    @Test("An inverted buff is displayed with the opposite sign")
    func invertedBuffDisplayValue() async throws {
        let fleet = try await makeFleet([.shieldBurst(.shieldHarmonizingCharge)])
        let buffs = await hullBuffs(fleet.engine, on: Self.hullID(1))
        let buff = try #require(buffs.first { $0.id == 10 })

        #expect(buff.visibility == .inverted)
        #expect(buff.value < 0)
        #expect(buff.displayValue == -buff.value)
    }

    @Test("Environment buffs are listed on every hull and on the environment effect")
    func environmentBuffs() async throws {
        let engine = DogmaEngine()
        let environmentID = try await engine.edit { fit -> EnvironmentID in
            let id = try fit.environment.add(.darknessWeather1).id
            for _ in 0..<2 {
                let pilot = try fit.pilots.add(skillLevel: 5)
                try pilot.hull.set(typeID: .rifter)
            }
            return id
        }

        let (broadcast, first, second) = await engine.evaluate { stats in
            (stats[environmentID].warfareBuffs, stats[Self.hullID(1)].warfareBuffs, stats[Self.hullID(2)].warfareBuffs)
        }

        // Pinned SDE values: Darkness Weather 1 carries buff 97 at -30 and buff 98 at 50.
        #expect(broadcast.map(\.id) == [97, 98])
        #expect(broadcast.map(\.value) == [-30, 50])
        for applied in [first, second] {
            #expect(applied.map(\.id) == [97, 98])
            #expect(applied.allSatisfy { $0.sources.map(\.entityID) == [environmentID.rawValue] })
        }
    }
}
