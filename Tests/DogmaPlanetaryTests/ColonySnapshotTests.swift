//
//  ColonySnapshotTests.swift
//  DogmaKit
//
//  Rebuilding a colony from a snapshot (`Colony.init(snapshot:catalog:)`). The fixture is a
//  typical P1 colony on Barren: extractor -> storage -> Basic Industry (Water) -> launchpad.
//  Key cases: a processor mid-cycle and the choice of the extractor's current cycle.
//

import Foundation
import Testing
@testable import DogmaPlanetary

@Suite("Colony snapshot")
struct ColonySnapshotTests {

    let catalog: PlanetaryCatalog
    init() throws { catalog = try PlanetaryCatalog.bundled() }

    static let t0 = Date(timeIntervalSince1970: 1_790_000_000)
    static func at(_ seconds: Int) -> Date { t0.addingTimeInterval(TimeInterval(seconds)) }

    // Barren
    static let barren: TypeID = 2016
    static let commandCenter: TypeID = 2524
    static let extractorType: TypeID = 2848
    static let storageType: TypeID = 2541
    static let basicIndustry: TypeID = 2473
    static let launchpadType: TypeID = 2544
    // Water: 3000 Aqueous Liquids make 20 Water per 30 minutes
    static let aqueousLiquids: TypeID = 2268
    static let water: TypeID = 3645
    static let waterSchematic: SchematicID = 121

    enum ID {
        static let cc: Int64 = 1001, ecu: Int64 = 1002, storage: Int64 = 1003, factory: Int64 = 1004, launchpad: Int64 = 1005
    }

    static func extractorPin(installedAgo: Int = 36_000, lasting: Int = 14 * 86_400 / 2,
                             lastCycleStart: Date? = at(0), quantity: Int? = 6965) -> ColonySnapshot.Pin {
        .init(pinID: ID.ecu, typeID: extractorType,
              installTime: at(-installedAgo), expiryTime: at(-installedAgo + lasting), lastCycleStart: lastCycleStart,
              extractor: .init(productTypeID: aqueousLiquids, cycleTime: 1800, quantityPerCycle: quantity, headCount: 6))
    }

    static func factoryPin(schematic: SchematicID? = waterSchematic, typeID: TypeID = basicIndustry,
                           lastCycleStart: Date? = at(-600), buffer: Int = 3000) -> ColonySnapshot.Pin {
        .init(pinID: ID.factory, typeID: typeID, schematicID: schematic, lastCycleStart: lastCycleStart,
              contents: buffer > 0 ? [.init(typeID: aqueousLiquids, quantity: buffer)] : [])
    }

    static func snapshot(extractor: ColonySnapshot.Pin = extractorPin(),
                         factory: ColonySnapshot.Pin = factoryPin(),
                         extraPins: [ColonySnapshot.Pin] = [],
                         extraRoutes: [ColonySnapshot.Route] = []) -> ColonySnapshot {
        ColonySnapshot(
            snapshotTime: t0, planetTypeID: barren, upgradeLevel: 4,
            pins: [
                .init(pinID: ID.cc, typeID: commandCenter),
                extractor,
                .init(pinID: ID.storage, typeID: storageType, contents: [.init(typeID: aqueousLiquids, quantity: 5000)]),
                factory,
                .init(pinID: ID.launchpad, typeID: launchpadType, contents: [.init(typeID: water, quantity: 100)]),
            ] + extraPins,
            routes: [
                .init(routeID: 3, sourcePinID: ID.factory, destinationPinID: ID.launchpad, typeID: water, quantity: 20),
                .init(routeID: 2, sourcePinID: ID.storage, destinationPinID: ID.factory, typeID: aqueousLiquids, quantity: 3000),
                .init(routeID: 1, sourcePinID: ID.ecu, destinationPinID: ID.storage, typeID: aqueousLiquids, quantity: 6965),
            ] + extraRoutes,
            links: [
                .init(sourcePinID: ID.cc, destinationPinID: ID.ecu),
                .init(sourcePinID: ID.cc, destinationPinID: ID.storage, level: 1),
                .init(sourcePinID: ID.storage, destinationPinID: ID.factory),
                .init(sourcePinID: ID.storage, destinationPinID: ID.launchpad),
            ])
    }

    func colony(_ snapshot: ColonySnapshot = snapshot()) throws -> Colony {
        try Colony(snapshot: snapshot, catalog: catalog)
    }

    // MARK: - Layout

    @Test("Layout: pins in snapshot order, roles, capacities, contents")
    func layout() throws {
        let colony = try colony()
        #expect(colony.warnings.isEmpty)
        #expect(colony.snapshotTime == Self.t0)
        #expect(colony.upgradeLevel == 4)
        #expect(colony.pins.map(\.pinID) == [ID.cc, ID.ecu, ID.storage, ID.factory, ID.launchpad])
        #expect(colony.pins.map(\.kind) == [.commandCenter, .extractor, .storage, .processor, .launchpad])
        #expect(colony.pins.map(\.capacity) == [500, 0, 12000, 0, 10000])
        let storage = try #require(colony[pinID: ID.storage])
        #expect(storage.role == .storage)
        #expect(storage.contents[Self.aqueousLiquids] == 5000)
        #expect(storage.contents.volume(in: catalog) == 25)            // 5000 x 0.005 m3
        #expect(colony.links.count == 4)
        #expect(colony.links[1].level == 1)
    }

    @Test("Routes: outgoing sorted by route id, incoming by source")
    func routes() throws {
        let extra = ColonySnapshot.Route(routeID: 0, sourcePinID: ID.storage, destinationPinID: ID.launchpad,
                                         typeID: Self.aqueousLiquids)
        let colony = try colony(Self.snapshot(extraRoutes: [extra]))
        let storage = try #require(colony.index(ofPinID: ID.storage))
        let factory = try #require(colony.index(ofPinID: ID.factory))
        let launchpad = try #require(colony.index(ofPinID: ID.launchpad))
        #expect(colony.routes.map(\.routeID) == [1, 0, 2, 3])   // sources: extractor < storage < factory
        #expect(colony.routes(from: storage).map(\.routeID) == [0, 2])
        #expect(colony.routes(from: launchpad).isEmpty)
        #expect(colony.routes(to: launchpad).map(\.routeID) == [0, 3])
        #expect(colony.routes(to: factory).map(\.source) == [storage])
        #expect(colony.routes(from: factory).first?.quantity == 20)
    }

    // MARK: - Processor

    @Test("A processor mid-cycle delivers the running cycle and keeps its buffer for the next")
    func processorRunning() throws {
        let colony = try colony()
        let factory = try #require(colony[pinID: ID.factory])
        guard case .processor(let processor) = factory.role else { Issue.record("not a processor"); return }
        #expect(processor.schematicID == Self.waterSchematic)
        #expect(processor.runningCycleEnd == Self.at(1200))      // start -600 + 1800
        #expect(factory.contents[Self.aqueousLiquids] == 3000)   // buffer untouched
        #expect(colony.schematic(of: factory.id)?.output.typeID == Self.water)
    }

    @Test("A processor whose cycle ended at or before the snapshot is idle")
    func processorIdle() throws {
        for start in [Self.at(-1800), Self.at(-86_400), nil] {
            let colony = try colony(Self.snapshot(factory: Self.factoryPin(lastCycleStart: start)))
            guard case .processor(let processor) = try #require(colony[pinID: ID.factory]).role else {
                Issue.record("not a processor"); return
            }
            #expect(processor.runningCycleEnd == nil)
        }
    }

    @Test("A processor without a schematic or with an unsupported one gives warnings")
    func processorWarnings() throws {
        let bare = try colony(Self.snapshot(factory: Self.factoryPin(schematic: nil)))
        #expect(bare.warnings == [.processorWithoutSchematic(pinID: ID.factory)])
        // Mechanical Parts (P2) on a Basic Industry Facility.
        let foreign = try colony(Self.snapshot(factory: Self.factoryPin(schematic: 73)))
        #expect(foreign.warnings == [.schematicNotSupported(pinID: ID.factory, schematicID: 73)])
    }

    // MARK: - Extractor

    func extractor(_ colony: Colony) throws -> Colony.Extractor {
        guard case .extractor(let extractor) = try #require(colony[pinID: ID.ecu]).role else {
            Issue.record("not an extractor")
            throw CancellationError()
        }
        return extractor
    }

    @Test("Extractor current cycle is the one running at the snapshot; a cycle ending at T0 is already delivered")
    func extractorPending() throws {
        // Installed 10 h ago, 30 minute cycle: cycles 0...19 are done, cycle 19 ends exactly at T0.
        let colony = try colony()
        let extractor = try extractor(colony)
        let program = try #require(extractor.program)
        #expect(extractor.pendingCycle == 20)
        #expect(program.cycleEnd(20) == Self.at(1800))
        #expect(program.quantityPerCycle == 6965)
        #expect(program.decayFactor == catalog.extractor.decayFactor)
        #expect(extractor.headCount == 6)
        #expect(extractor.productTypeID == Self.aqueousLiquids)
    }

    @Test("Extractor waits for cycle 0 before installation and for nothing after expiry")
    func extractorBounds() throws {
        let future = try colony(Self.snapshot(extractor: Self.extractorPin(installedAgo: -3600, lastCycleStart: nil)))
        #expect(try extractor(future).pendingCycle == 0)
        let expired = try colony(Self.snapshot(extractor: Self.extractorPin(installedAgo: 86_400, lasting: 36_000)))
        #expect(try extractor(expired).pendingCycle == nil)
        #expect(try extractor(expired).program?.cycleCount == 20)
    }

    @Test("Extractor without quantity per cycle is not modelled; a skewed last cycle start gives a warning")
    func extractorWarnings() throws {
        let bare = try colony(Self.snapshot(extractor: Self.extractorPin(quantity: nil)))
        #expect(try extractor(bare).program == nil)
        #expect(try extractor(bare).pendingCycle == nil)
        #expect(bare.warnings == [.extractorNotConfigured(pinID: ID.ecu)])

        let skewed = try colony(Self.snapshot(extractor: Self.extractorPin(lastCycleStart: Self.at(-7))))
        #expect(skewed.warnings == [.extractorCycleMisaligned(pinID: ID.ecu)])
        #expect(try extractor(skewed).pendingCycle == 20)        // the grid starts at installation
    }

    // MARK: - Contents and planet

    @Test("Unknown commodities are dropped, duplicates are summed, zeros are not stored")
    func contents() throws {
        let pin = ColonySnapshot.Pin(pinID: 2000, typeID: Self.storageType, contents: [
            .init(typeID: Self.water, quantity: 10), .init(typeID: 34, quantity: 5),
            .init(typeID: Self.water, quantity: 15), .init(typeID: Self.aqueousLiquids, quantity: 0),
        ])
        let colony = try colony(Self.snapshot(extraPins: [pin]))
        #expect(colony.warnings == [.unknownCommodity(pinID: 2000, typeID: 34)])
        let contents = try #require(colony[pinID: 2000]).contents
        #expect(contents.items == [.init(typeID: Self.water, quantity: 25)])
    }

    @Test("A pin from another planet gives a warning")
    func planetMismatch() throws {
        let temperateStorage = ColonySnapshot.Pin(pinID: 2000, typeID: 2562)
        let colony = try colony(Self.snapshot(extraPins: [temperateStorage]))
        #expect(colony.warnings == [.planetMismatch(pinID: 2000)])
    }

    // MARK: - Errors

    @Test("An inconsistent snapshot is rejected")
    func errors() {
        let snapshot = Self.snapshot()
        func expectError(_ error: ColonyError, _ mutate: (inout ColonySnapshot) -> Void) {
            var broken = snapshot
            mutate(&broken)
            #expect(throws: error) { try Colony(snapshot: broken, catalog: catalog) }
        }
        expectError(.duplicatePin(pinID: ID.cc)) { $0.pins.append(.init(pinID: ID.cc, typeID: Self.storageType)) }
        // Barren Aqueous Liquid Extractor is in legacy group 1026, which the catalog excludes.
        expectError(.unknownPinType(pinID: 2000, typeID: 2409)) { $0.pins.append(.init(pinID: 2000, typeID: 2409)) }
        expectError(.unknownPin(pinID: 9)) {
            $0.routes.append(.init(routeID: 9, sourcePinID: ID.storage, destinationPinID: 9, typeID: Self.water))
        }
        expectError(.unknownPin(pinID: 8)) { $0.links.append(.init(sourcePinID: 8, destinationPinID: ID.cc)) }
        expectError(.unknownPin(pinID: 7)) {
            $0.routes.append(.init(routeID: 9, sourcePinID: ID.storage, destinationPinID: ID.launchpad,
                                   typeID: Self.water, waypoints: [7]))
        }
        expectError(.unknownSchematic(pinID: ID.factory, schematicID: 9999)) { $0.pins[3].schematicID = 9999 }
        expectError(.unknownRouteCommodity(routeID: 9, typeID: 34)) {
            $0.routes.append(.init(routeID: 9, sourcePinID: ID.storage, destinationPinID: ID.launchpad, typeID: 34))
        }
    }
}
