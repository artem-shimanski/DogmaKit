//
//  ColonySimulationTests.swift
//  DogmaKit
//
//  Colony simulation (`ColonySimulation`). The fixture is the P1 Barren colony from
//  `ColonySnapshotTests`: extractor (Aqueous Liquids, 30 min) -> storage -> Basic Industry
//  (3000 Aqueous Liquids make 20 Water, 30 min) -> launchpad. The factory is mid-cycle at the
//  snapshot (start -600, end +1200) with a full buffer.
//

import Foundation
import Testing
@testable import DogmaPlanetary

@Suite("Colony simulation")
struct ColonySimulationTests {

    typealias Fixture = ColonySnapshotTests
    typealias ID = ColonySnapshotTests.ID

    let catalog: PlanetaryCatalog
    init() throws { catalog = try PlanetaryCatalog.bundled() }

    func simulation(_ snapshot: ColonySnapshot = Fixture.snapshot()) throws -> ColonySimulation {
        ColonySimulation(try Colony(snapshot: snapshot, catalog: catalog))
    }

    func index(_ simulation: ColonySimulation, _ pinID: Int64) throws -> Colony.PinIndex {
        try #require(simulation.colony.index(ofPinID: pinID))
    }

    /// Total commodities across all pins.
    func total(_ colony: Colony) -> Inventory {
        var result = Inventory()
        for pin in colony.pins {
            for item in pin.contents { result[item.typeID] += item.quantity }
        }
        return result
    }

    // MARK: - Main chain

    @Test("The factory finishes its running cycle and then works without idling")
    func chain() throws {
        var sim = try simulation()
        let forecast = sim.run(until: Fixture.at(7200))
        let factory = try index(sim, ID.factory)
        let launchpad = try index(sim, ID.launchpad)
        // Cycle ends: +1200 (running), +3000, +4800, +6600.
        #expect(forecast[factory].cycles == 4)
        #expect(forecast[factory].produced[Fixture.water] == 80)
        #expect(forecast[factory].consumed[Fixture.aqueousLiquids] == 12000)  // starts at +1200, +3000, +4800, +6600
        #expect(sim.colony[launchpad].contents[Fixture.water] == 180)
        #expect(forecast.utilization(of: factory) == 1)
        #expect(!forecast.events.contains { if case .processorIdle = $0 { true } else { false } })
        #expect(forecast.wasted.isEmpty)
        // The factory is mid-cycle again: start +6600, end +8400.
        guard case .processor(let processor) = sim.colony[factory].role else { Issue.record("not a processor"); return }
        #expect(processor.runningCycleEnd == Fixture.at(8400))
        #expect(processor.lastCycleStart == Fixture.at(6600))
        #expect(sim.time == Fixture.at(7200))
    }

    @Test("Extractor output over a window matches the formula when storage has room")
    func extractorYield() throws {
        var sim = try simulation()
        let forecast = sim.run(until: Fixture.at(4 * 3600))
        let ecu = try index(sim, ID.ecu)
        guard case .extractor(let extractor) = sim.colony[ecu].role, let program = extractor.program else {
            Issue.record("no program"); return
        }
        #expect(forecast[ecu].cycles == 8)
        #expect(forecast[ecu].produced[Fixture.aqueousLiquids] == program.yield(from: Fixture.t0, to: Fixture.at(4 * 3600)))
        #expect(forecast[ecu].wasted.isEmpty)
        #expect(extractor.pendingCycle == 28)
    }

    @Test("Mass is conserved: initial + produced - wasted - consumed = final")
    func conservation() throws {
        var sim = try simulation()
        let before = total(sim.colony)
        let forecast = sim.run(until: Fixture.at(3 * 86_400))
        let after = total(sim.colony)
        for typeID in [Fixture.aqueousLiquids, Fixture.water] {
            #expect(before[typeID] + forecast.balance(of: typeID) == after[typeID], "\(typeID.rawValue)")
        }
    }

    // MARK: - Idling and waste

    @Test("Empty storage: the running cycle delivers, then the factory stops")
    func starvation() throws {
        var snapshot = Fixture.snapshot(factory: Fixture.factoryPin(buffer: 0))
        snapshot.pins[2].contents = []                                         // storage empty
        snapshot.pins[1] = Fixture.extractorPin(installedAgo: 86_400, lasting: 36_000)  // extractor program finished
        var sim = try simulation(snapshot)
        let factory = try index(sim, ID.factory)
        let forecast = sim.run(until: Fixture.at(7200))
        #expect(forecast[factory].cycles == 1)
        #expect(forecast.events == [.processorIdle(factory, at: Fixture.at(1200))])
        #expect(forecast.utilization(of: factory) == 1200.0 / 7200)
    }

    @Test("An idle factory resumes when storage receives input from the extractor")
    func resume() throws {
        var snapshot = Fixture.snapshot(factory: Fixture.factoryPin(lastCycleStart: nil, buffer: 0))
        snapshot.pins[2].contents = []
        var sim = try simulation(snapshot)
        let factory = try index(sim, ID.factory)
        let forecast = sim.run(until: Fixture.at(3000))
        // Idle at T0; at +1800 the extractor delivered 3000 or more to storage, which pushed it to the factory.
        #expect(forecast.events.prefix(2) == [.processorIdle(factory, at: Fixture.t0),
                                               .processorResumed(factory, at: Fixture.at(1800))])
        #expect(forecast[factory].consumed[Fixture.aqueousLiquids] == 3000)
    }

    @Test("A factory without an output route works and its output is wasted")
    func noOutputRoute() throws {
        var snapshot = Fixture.snapshot()
        snapshot.routes.removeAll { $0.sourcePinID == ID.factory }
        var sim = try simulation(snapshot)
        let factory = try index(sim, ID.factory)
        let forecast = sim.run(until: Fixture.at(7200))
        #expect(forecast[factory].cycles == 4)
        #expect(forecast[factory].wasted[Fixture.water] == 80)
        #expect(forecast[factory].consumed[Fixture.aqueousLiquids] == 12000)  // inputs are consumed
        #expect(forecast.events.first == .outputWasted(factory, typeID: Fixture.water, at: Fixture.at(1200)))
    }

    @Test("Overfilled command center: event and extractor waste, volume stays within capacity")
    func storageFull() throws {
        // The extractor feeds the command center (500 m3 = 100,000 Aqueous Liquids); no factory.
        var snapshot = Fixture.snapshot()
        snapshot.pins.removeAll { $0.pinID == ID.factory }
        snapshot.routes = [.init(routeID: 1, sourcePinID: ID.ecu, destinationPinID: ID.cc, typeID: Fixture.aqueousLiquids)]
        snapshot.links = []
        var sim = try simulation(snapshot)
        let cc = try index(sim, ID.cc)
        let ecu = try index(sim, ID.ecu)
        let forecast = sim.run(until: Fixture.at(86_400))
        #expect(sim.colony[cc].contents[Fixture.aqueousLiquids] == 100_000)
        #expect(sim.colony[cc].contents.volume(in: catalog) <= 500)
        #expect(forecast[ecu].wasted[Fixture.aqueousLiquids] > 0)
        let full = forecast.events.filter { if case .storageFull(cc, _) = $0 { true } else { false } }
        #expect(full.count == 1)
        #expect(forecast.events.contains { if case .outputWasted(ecu, _, _) = $0 { true } else { false } })
    }

    @Test("End of the extractor program is an event, with no output afterwards")
    func extractorFinished() throws {
        // Installed 10 h ago for 11 h: 2 cycles remain (+1800, +3600).
        var sim = try simulation(Fixture.snapshot(extractor: Fixture.extractorPin(lasting: 39_600)))
        let ecu = try index(sim, ID.ecu)
        let forecast = sim.run(until: Fixture.at(86_400))
        #expect(forecast[ecu].cycles == 2)
        #expect(forecast.events.contains(.extractorFinished(ecu, at: Fixture.at(3600))))
    }

    // MARK: - Windows and determinism

    @Test("Two consecutive windows equal one and do not double count")
    func windows() throws {
        var whole = try simulation()
        let all = whole.run(until: Fixture.at(36_000))
        var split = try simulation()
        let first = split.run(until: Fixture.at(10_800))
        let second = split.run(until: Fixture.at(36_000))
        #expect(first.to == second.from)
        for typeID in [Fixture.aqueousLiquids, Fixture.water] {
            #expect(first.produced[typeID] + second.produced[typeID] == all.produced[typeID])
            #expect(first.consumed[typeID] + second.consumed[typeID] == all.consumed[typeID])
        }
        #expect(whole.colony.pins.map(\.contents) == split.colony.pins.map(\.contents))
        #expect(first.events + second.events == all.events)
    }

    @Test("Pin order in the input does not affect the result")
    func determinism() throws {
        // Two factories on one storage that cannot supply both.
        var snapshot = Fixture.snapshot()
        snapshot.pins.append(.init(pinID: 1006, typeID: Fixture.basicIndustry, schematicID: Fixture.waterSchematic))
        snapshot.routes.append(.init(routeID: 4, sourcePinID: ID.storage, destinationPinID: 1006, typeID: Fixture.aqueousLiquids))
        snapshot.routes.append(.init(routeID: 5, sourcePinID: 1006, destinationPinID: ID.launchpad, typeID: Fixture.water))
        var reversed = snapshot
        reversed.pins.reverse()
        reversed.routes.reverse()

        func run(_ snapshot: ColonySnapshot) throws -> [Int64: Forecast.PinStats] {
            var sim = try simulation(snapshot)
            let forecast = sim.run(until: Fixture.at(2 * 86_400))
            return Dictionary(uniqueKeysWithValues: sim.colony.pins.map { ($0.pinID, forecast[$0.id]) })
        }
        #expect(try run(snapshot) == run(reversed))
    }

    // MARK: - Edge cases

    @Test("A horizon in the past gives an empty window and does not restart")
    func pastHorizon() throws {
        var sim = try simulation()
        _ = sim.run(until: Fixture.at(600))
        let empty = sim.run(until: Fixture.at(300))
        #expect(empty.duration == 0)
        #expect(empty.produced.isEmpty && empty.consumed.isEmpty && empty.events.isEmpty)
        #expect(sim.time == Fixture.at(600))
    }

    @Test("The event cap stops the run")
    func truncation() throws {
        var sim = try simulation()
        let forecast = sim.run(until: Fixture.at(86_400), options: .init(maxEvents: 1))
        #expect(forecast.isTruncated)
        #expect(sim.time == Fixture.at(1200))
    }

    @Test("Timeline: initial state and every contents change")
    func timeline() throws {
        var sim = try simulation()
        let launchpad = try index(sim, ID.launchpad)
        let forecast = sim.run(until: Fixture.at(3600), options: .init(timeline: true))
        let entries = forecast.timeline.filter { $0.pin == launchpad }
        #expect(entries.map(\.date) == [Fixture.t0, Fixture.at(1200), Fixture.at(3000)])
        #expect(entries.map { $0.contents[Fixture.water] } == [100, 120, 140])
        #expect(try sim.run(until: Fixture.at(7200)).timeline.isEmpty)    // off by default
    }
}
