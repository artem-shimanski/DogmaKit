//
//  ColonyReadTests.swift
//  DogmaKit
//
//  Read API of `Colony`: pin names, storage, rates, next events, projection and forecast queries.
//

import Foundation
import Testing
@testable import DogmaPlanetary

@Suite("Colony read API")
struct ColonyReadTests {

    typealias Fixture = ColonySnapshotTests
    typealias ID = ColonySnapshotTests.ID

    let catalog: PlanetaryCatalog
    init() throws { catalog = try PlanetaryCatalog.bundled() }

    func colony(_ snapshot: ColonySnapshot = Fixture.snapshot()) throws -> Colony {
        try Colony(snapshot: snapshot, catalog: catalog)
    }

    @Test("Pin name is base-34 of the pin id")
    func pinNames() throws {
        #expect(Colony.pinName(1001) == "GU-111")
        #expect(Colony.pinName(1_000_000_012_345) == "YR-CS9")
        #expect(Colony.pinName(1_047_213_590_893) == "6R-EFE")
        #expect(try colony()[pinID: ID.factory]?.name == "JU-111")
    }

    @Test("Storage used, free and fill")
    func storage() throws {
        let colony = try colony()
        let storage = try #require(colony.index(ofPinID: ID.storage))
        let factory = try #require(colony.index(ofPinID: ID.factory))
        #expect(colony.usedVolume(of: storage) == 25)
        #expect(colony.freeVolume(of: storage) == 11975)
        #expect(colony.fill(of: storage) == 25.0 / 12000)
        #expect(colony.fill(of: factory) == nil)
        #expect(colony.freeVolume(of: factory) == 0)
    }

    @Test("Next events of pins")
    func nextEvents() throws {
        let colony = try colony()
        #expect(colony.nextEvent(of: try #require(colony.index(ofPinID: ID.factory))) == Fixture.at(1200))
        #expect(colony.nextEvent(of: try #require(colony.index(ofPinID: ID.ecu))) == Fixture.at(1800))
        #expect(colony.nextEvent(of: try #require(colony.index(ofPinID: ID.storage))) == nil)
    }

    @Test("Rates: processor by schematic, extractor averaged over the rest of the program")
    func rates() throws {
        let colony = try colony()
        let factory = colony.hourlyRate(of: try #require(colony.index(ofPinID: ID.factory)))
        #expect(factory.outputs == [Fixture.water: 40])
        #expect(factory.inputs == [Fixture.aqueousLiquids: 6000])

        let ecu = try #require(colony.index(ofPinID: ID.ecu))
        guard case .extractor(let extractor) = colony[ecu].role, let program = extractor.program,
              let pending = extractor.pendingCycle else { Issue.record("no program"); return }
        let remaining = (pending..<program.cycleCount).reduce(0) { $0 + program.yield(cycle: $1) }
        let hours = Double((program.cycleCount - pending) * 1800) / 3600
        #expect(colony.hourlyRate(of: ecu).outputs[Fixture.aqueousLiquids] == Double(remaining) / hours)
        #expect(colony.hourlyRate(of: try #require(colony.index(ofPinID: ID.storage))) == .init())
    }

    @Test("Projection of catch-up plus future equals a single run")
    func projection() throws {
        let colony = try colony()
        let projection = colony.project(now: Fixture.at(5 * 3600), until: Fixture.at(48 * 3600))
        var whole = ColonySimulation(colony)
        let all = whole.run(until: Fixture.at(48 * 3600))
        #expect(projection.elapsed.to == Fixture.at(5 * 3600))
        #expect(projection.upcoming.from == Fixture.at(5 * 3600))
        for typeID in [Fixture.aqueousLiquids, Fixture.water] {
            #expect(projection.elapsed.produced[typeID] + projection.upcoming.produced[typeID] == all.produced[typeID])
        }
        #expect(projection.final.pins.map(\.contents) == whole.colony.pins.map(\.contents))

        var head = ColonySimulation(colony)
        _ = head.run(until: Fixture.at(5 * 3600))
        #expect(projection.current.pins.map(\.contents) == head.colony.pins.map(\.contents))
    }

    @Test("Now before the snapshot gives empty catch-up")
    func projectionBeforeSnapshot() throws {
        let projection = try colony().project(now: Fixture.at(-3600), until: Fixture.at(3600))
        #expect(projection.elapsed.duration == 0)
        #expect(projection.upcoming.from == Fixture.t0)
    }

    @Test("Forecast queries: idle, overflow, program end, contents on the timeline")
    func forecastQueries() throws {
        // The factory without input stops after its running cycle; the extractor feeds the CC and overflows it.
        var snapshot = Fixture.snapshot(factory: Fixture.factoryPin(buffer: 0),
                                        extraPins: [], extraRoutes: [])
        snapshot.pins[2].contents = []
        snapshot.pins[1] = Fixture.extractorPin(lasting: 36_000 + 5 * 86_400)
        snapshot.routes = [
            .init(routeID: 1, sourcePinID: ID.ecu, destinationPinID: ID.cc, typeID: Fixture.aqueousLiquids),
            .init(routeID: 3, sourcePinID: ID.factory, destinationPinID: ID.launchpad, typeID: Fixture.water),
        ]
        let colony = try colony(snapshot)
        let factory = try #require(colony.index(ofPinID: ID.factory))
        let cc = try #require(colony.index(ofPinID: ID.cc))
        let ecu = try #require(colony.index(ofPinID: ID.ecu))
        let launchpad = try #require(colony.index(ofPinID: ID.launchpad))
        var simulation = ColonySimulation(colony)
        let forecast = simulation.run(until: Fixture.at(6 * 86_400), options: .init(timeline: true))

        #expect(forecast.idleSince(factory) == Fixture.at(1200))
        let full = try #require(forecast.storageFull(cc))
        #expect(full > Fixture.t0)
        #expect(forecast.extractorFinished(ecu) == Fixture.at(5 * 86_400))
        #expect(forecast.contents(of: launchpad, at: Fixture.at(600))?[Fixture.water] == 100)
        #expect(forecast.contents(of: launchpad, at: Fixture.at(1200))?[Fixture.water] == 120)
        #expect(forecast.contents(of: launchpad, at: Fixture.at(-1)) == nil)
    }
}
