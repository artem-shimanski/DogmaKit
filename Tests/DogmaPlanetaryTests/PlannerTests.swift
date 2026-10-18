//
//  PlannerTests.swift
//  DogmaKit
//
//  Planner: colony to snapshot round trip, layout resources and connectivity
//  (`ColonyFitting`), and customs fees (`Customs`).
//

import Foundation
import Testing
@testable import DogmaPlanetary

@Suite("Planner")
struct PlannerTests {

    typealias Fixture = ColonySnapshotTests
    typealias ID = ColonySnapshotTests.ID

    let catalog: PlanetaryCatalog
    init() throws { catalog = try PlanetaryCatalog.bundled() }

    func colony(_ snapshot: ColonySnapshot = Fixture.snapshot()) throws -> Colony {
        try Colony(snapshot: snapshot, catalog: catalog)
    }

    // MARK: - Colony to snapshot

    @Test("A colony snapshot rebuilds the same colony")
    func roundTrip() throws {
        let original = try colony()
        let restored = try colony(original.snapshot())
        #expect(restored.snapshotTime == original.snapshotTime)
        #expect(restored.upgradeLevel == original.upgradeLevel)
        #expect(restored.pins.map(\.pinID) == original.pins.map(\.pinID))
        #expect(restored.pins.map(\.contents) == original.pins.map(\.contents))
        #expect(restored.pins.map(\.role) == original.pins.map(\.role))
        #expect(restored.routes == original.routes)
        #expect(restored.links == original.links)
        #expect(restored.warnings.isEmpty)
    }

    @Test("Saving a simulation through a snapshot does not change the result")
    func simulationThroughSnapshot() throws {
        let colony = try colony()
        var straight = ColonySimulation(colony)
        _ = straight.run(until: Fixture.at(30 * 3600))

        var first = ColonySimulation(colony)
        _ = first.run(until: Fixture.at(7 * 3600 + 100))      // mid-cycle
        let saved = first.snapshot
        #expect(saved.snapshotTime == Fixture.at(7 * 3600 + 100))
        var resumed = ColonySimulation(try self.colony(saved))
        _ = resumed.run(until: Fixture.at(30 * 3600))

        #expect(resumed.colony.pins.map(\.contents) == straight.colony.pins.map(\.contents))
        #expect(resumed.colony.pins.map(\.role) == straight.colony.pins.map(\.role))
    }

    // MARK: - Resources and connectivity

    /// Fixture with waypoints on the routes that do not follow a direct link.
    static func linkedSnapshot(level: Int = 4) -> ColonySnapshot {
        var snapshot = Fixture.snapshot()
        snapshot.upgradeLevel = level
        snapshot.routes[0].waypoints = [ID.storage]          // factory -> storage -> launchpad
        snapshot.routes[2].waypoints = [ID.cc]               // extractor -> CC -> storage
        return snapshot
    }

    @Test("CPU/PG: pins, extractor heads and links against the command center level")
    func resources() throws {
        let fitting = try colony(Self.linkedSnapshot()).fitting
        #expect(fitting.issues.contains(.linkLengthUnknown))
        #expect(fitting.issues.filter { $0 != .linkLengthUnknown }.isEmpty)
        // Pins: extractor 400 + 6 x 110, storage 500, Basic Industry 200, launchpad 3600, CC 0.
        let pinsCPU: Double = 400 + 660 + 500 + 200 + 3600
        let pinsPower: Double = 2600 + 3300 + 700 + 800 + 700
        // Zero-length links (no radius): base 15/10 only; the level scales just the per-km part,
        // so a level 1 link costs the same as level 0.
        let linksCPU: Double = 4 * 15
        let linksPower: Double = 4 * 10
        #expect(abs(fitting.cpu.used - (pinsCPU + linksCPU)) < 1e-9)
        #expect(abs(fitting.power.used - (pinsPower + linksPower)) < 1e-9)
        #expect(fitting.cpu.total == 21315 && fitting.power.total == 17000)
        #expect(!fitting.cpu.isOverloaded && !fitting.power.isOverloaded)
        #expect(fitting.pins.count == 5)
    }

    @Test("Overload at level 0")
    func overload() throws {
        let fitting = try colony(Self.linkedSnapshot(level: 0)).fitting
        #expect(fitting.cpu.total == 1675)
        #expect(fitting.issues.contains(.cpuOverloaded))
        #expect(fitting.issues.contains(.powerOverloaded))
        #expect(fitting.cpu.free < 0)
    }

    @Test("Link length is an arc along the planet surface")
    func linkLength() throws {
        var snapshot = Self.linkedSnapshot()
        snapshot.planetRadius = 5_060_000
        // latitude is the polar angle: equator = pi/2
        snapshot.pins[0].latitude = .pi / 2; snapshot.pins[0].longitude = 0           // CC
        snapshot.pins[1].latitude = .pi / 2; snapshot.pins[1].longitude = .pi / 2    // extractor, a quarter of the equator
        let fitting = try colony(snapshot).fitting
        #expect(!fitting.issues.contains(.linkLengthUnknown))
        let link = fitting.links[0]                                                   // CC - extractor, level 0
        let expected = 5060 * Double.pi / 2
        #expect(abs((link.length ?? 0) - expected) < 1e-6)
        #expect(link.cpu == (15 + 0.2 * expected).rounded(.up))        // link load rounds up
        #expect(link.power == (10 + 0.15 * expected).rounded(.up))
    }

    @Test("Route without a link, no CC, too many heads, unknown level")
    func issues() throws {
        // The base fixture: extractor -> storage and factory -> launchpad have no waypoints and bypass the links.
        let unlinked = try colony().fitting
        #expect(unlinked.issues.contains(.routeNotLinked(routeID: 1)))
        #expect(unlinked.issues.contains(.routeNotLinked(routeID: 3)))
        #expect(!unlinked.issues.contains(.routeNotLinked(routeID: 2)))

        var snapshot = Self.linkedSnapshot(level: 7)
        snapshot.pins[1].extractor?.headCount = 11
        let broken = try colony(snapshot)
        let ecu = try #require(broken.index(ofPinID: ID.ecu))
        #expect(broken.fitting.issues.contains(.invalidUpgradeLevel(7)))
        #expect(broken.fitting.issues.contains(.tooManyHeads(ecu, count: 11)))

        var noCC = Self.linkedSnapshot()
        noCC.pins.removeFirst()
        noCC.links.removeAll { $0.sourcePinID == ID.cc }
        noCC.routes[2].waypoints = []
        let fitting = try colony(noCC).fitting
        #expect(fitting.issues.contains(.noCommandCenter))
        #expect(fitting.cpu.total == 0)
    }

    // MARK: - Customs

    @Test("Customs: export, import, command center launch")
    func customs() {
        let goods = Inventory([.init(typeID: Fixture.water, quantity: 100),             // P1
                               .init(typeID: Fixture.aqueousLiquids, quantity: 1000),   // P0
                               .init(typeID: 34, quantity: 5)])                         // not PI
        let export = Customs.exportFee(for: goods, taxRate: 0.1, catalog: catalog)
        let expected: Double = 400.0 * 100.0 * 0.1 + 5.0 * 1000.0 * 0.1
        #expect(export == expected)
        #expect(Customs.importFee(for: goods, taxRate: 0.1, catalog: catalog) == export / 2)
        #expect(Customs.commandCenterLaunchFee(for: goods, taxRate: 0.1, catalog: catalog) == export * 1.5)
        #expect(Customs.baseValue(of: .p4) == 1_200_000)
    }
}
