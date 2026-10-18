//
//  ESIColonyTests.swift
//  DogmaKit
//
//  A real ESI colony (Barren, P2 Biocells from three ECUs): the raw responses of
//  `GET /characters/{id}/planets/` and `/planets/{planet_id}/`, plus the mapping
//  ESI -> `ColonySnapshot`. Checks parsing of real data, fitting of an in-game
//  (hence valid) layout and the simulation balance.
//

import Foundation
import Testing
@testable import DogmaPlanetary

private struct ESIPlanet: Decodable {
    var last_update: Date
    var planet_id: Int64
    var planet_type: String
    var upgrade_level: Int
    var num_pins: Int
}

private struct ESIColony: Decodable {
    struct Item: Decodable { var amount: Int; var type_id: UInt32 }
    struct Head: Decodable { var head_id: Int }
    struct ExtractorDetails: Decodable {
        var cycle_time: Int?
        var heads: [Head]
        var product_type_id: UInt32?
        var qty_per_cycle: Int?
    }
    struct Pin: Decodable {
        var pin_id: Int64
        var type_id: UInt32
        var latitude: Double
        var longitude: Double
        var schematic_id: UInt16?
        var install_time: Date?
        var expiry_time: Date?
        var last_cycle_start: Date?
        var contents: [Item]?
        var extractor_details: ExtractorDetails?
    }
    struct Route: Decodable {
        var route_id: Int64
        var source_pin_id: Int64
        var destination_pin_id: Int64
        var content_type_id: UInt32
        var quantity: Double
        var waypoints: [Int64]?
    }
    struct Link: Decodable { var source_pin_id: Int64; var destination_pin_id: Int64; var link_level: Int }
    var pins: [Pin]
    var routes: [Route]
    var links: [Link]
}

@Suite("ESI colony")
struct ESIColonyTests {

    static let planetsJSON = #"""
[{"last_update":"2026-10-15T08:20:47Z","num_pins":9,"owner_id":90000001,"planet_id":40159291,"planet_type":"barren","solar_system_id":30002506,"upgrade_level":4}]
"""#

    static let colonyJSON = #"""
{"links":[{"destination_pin_id":1020196651502,"link_level":0,"source_pin_id":1020196464386},{"destination_pin_id":1020196564402,"link_level":0,"source_pin_id":1020196464386},{"destination_pin_id":1020205643855,"link_level":0,"source_pin_id":1020196651494},{"destination_pin_id":1020196501383,"link_level":0,"source_pin_id":1020196464386},{"destination_pin_id":1020196651506,"link_level":0,"source_pin_id":1020196464386},{"destination_pin_id":1020196651508,"link_level":0,"source_pin_id":1020196464386},{"destination_pin_id":1020196651514,"link_level":0,"source_pin_id":1020196464386},{"destination_pin_id":1020196651494,"link_level":0,"source_pin_id":1020196464386}],"pins":[{"contents":[{"amount":40,"type_id":2396},{"amount":20,"type_id":2399}],"last_cycle_start":"2020-04-04T13:53:34Z","latitude":1.5032544136047363,"longitude":3.3328778743743896,"pin_id":1020196651508,"schematic_id":79,"type_id":2474},{"contents":[{"amount":870,"type_id":2329}],"latitude":1.4498237371444702,"longitude":3.367450714111328,"pin_id":1020196651514,"type_id":2544},{"contents":[],"expiry_time":"2026-10-20T08:20:46Z","extractor_details":{"cycle_time":7200,"head_radius":0.02442057803273201,"heads":[{"head_id":0,"latitude":1.1461316347122192,"longitude":3.228414297103882},{"head_id":5,"latitude":1.1780385971069336,"longitude":3.1866812705993652}],"product_type_id":2270,"qty_per_cycle":689},"install_time":"2026-10-15T08:20:46Z","last_cycle_start":"2026-10-15T08:20:46Z","latitude":1.1654142141342163,"longitude":3.2065632343292236,"pin_id":1020205643855,"type_id":2848},{"contents":[],"latitude":1.5000149011611938,"longitude":3.3656702041625977,"pin_id":1020196464386,"type_id":2524},{"contents":[{"amount":209063,"type_id":2267},{"amount":1480,"type_id":2396}],"latitude":1.4830513000488281,"longitude":3.3515877723693848,"pin_id":1020196651494,"type_id":2541},{"contents":[],"expiry_time":"2026-10-20T08:20:46Z","extractor_details":{"cycle_time":7200,"head_radius":0.024401959031820297,"heads":[{"head_id":0,"latitude":1.6261909008026123,"longitude":3.2499911785125732},{"head_id":5,"latitude":1.596855878829956,"longitude":3.2902746200561523}],"product_type_id":2288,"qty_per_cycle":1430},"install_time":"2026-10-15T08:20:46Z","last_cycle_start":"2026-10-15T08:20:46Z","latitude":1.6215156316757202,"longitude":3.253805160522461,"pin_id":1020196501383,"type_id":2848},{"contents":[{"amount":1465,"type_id":2288}],"last_cycle_start":"2020-04-04T13:23:34Z","latitude":1.5084550380706787,"longitude":3.401848554611206,"pin_id":1020196651502,"schematic_id":134,"type_id":2473},{"contents":[],"expiry_time":"2026-10-20T08:20:46Z","extractor_details":{"cycle_time":7200,"head_radius":0.024238821119070053,"heads":[{"head_id":0,"latitude":1.384714961051941,"longitude":3.4746904373168945},{"head_id":1,"latitude":1.4178682565689087,"longitude":3.43711519241333},{"head_id":2,"latitude":1.4337655305862427,"longitude":3.484583854675293},{"head_id":5,"latitude":1.3696039915084839,"longitude":3.4260668754577637},{"head_id":6,"latitude":1.3358781337738037,"longitude":3.464784622192383}],"product_type_id":2270,"qty_per_cycle":1642},"install_time":"2026-10-15T08:20:46Z","last_cycle_start":"2026-10-15T08:20:46Z","latitude":1.3720144033432007,"longitude":3.446371078491211,"pin_id":1020196564402,"type_id":2848},{"contents":[{"amount":944,"type_id":2270}],"last_cycle_start":"2020-04-04T13:23:34Z","latitude":1.5296248197555542,"longitude":3.3748626708984375,"pin_id":1020196651506,"schematic_id":127,"type_id":2473}],"routes":[{"content_type_id":2399,"destination_pin_id":1020196651494,"quantity":20.0,"route_id":714009219,"source_pin_id":1020196651506,"waypoints":[1020196464386]},{"content_type_id":2288,"destination_pin_id":1020196651502,"quantity":3000.0,"route_id":713858504,"source_pin_id":1020196651494,"waypoints":[1020196464386]},{"content_type_id":2396,"destination_pin_id":1020196651494,"quantity":20.0,"route_id":713858476,"source_pin_id":1020196651502,"waypoints":[1020196464386]},{"content_type_id":2270,"destination_pin_id":1020196651506,"quantity":3000.0,"route_id":713230255,"source_pin_id":1020196651494,"waypoints":[1020196464386]},{"content_type_id":2329,"destination_pin_id":1020196651514,"quantity":5.0,"route_id":713230256,"source_pin_id":1020196651508,"waypoints":[1020196464386]},{"content_type_id":2396,"destination_pin_id":1020196651508,"quantity":40.0,"route_id":713230257,"source_pin_id":1020196651494,"waypoints":[1020196464386]},{"content_type_id":2399,"destination_pin_id":1020196651508,"quantity":40.0,"route_id":713230258,"source_pin_id":1020196651494,"waypoints":[1020196464386]},{"content_type_id":2270,"destination_pin_id":1020196651494,"quantity":23640.0,"route_id":1658915964,"source_pin_id":1020196564402,"waypoints":[1020196464386]},{"content_type_id":2288,"destination_pin_id":1020196651494,"quantity":20592.0,"route_id":1658915965,"source_pin_id":1020196501383,"waypoints":[1020196464386]},{"content_type_id":2270,"destination_pin_id":1020196651494,"quantity":9920.0,"route_id":1658915966,"source_pin_id":1020205643855,"waypoints":[]}]}
"""#

    /// `radius` of planet 40159291 from the SDE `mapPlanets`.
    static let planetRadius = 1_660_000.0

    enum ID {
        static let biocells: Int64 = 1020196651508, launchpad: Int64 = 1020196651514, storage: Int64 = 1020196651494
        static let preciousMetals: Int64 = 1020196651506, biofuels: Int64 = 1020196651502
        static let extractors: [Int64] = [1020205643855, 1020196501383, 1020196564402]
    }

    let catalog: PlanetaryCatalog
    init() throws { catalog = try PlanetaryCatalog.bundled() }

    static func snapshot() throws -> ColonySnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let planet = try decoder.decode([ESIPlanet].self, from: Data(planetsJSON.utf8))[0]
        let colony = try decoder.decode(ESIColony.self, from: Data(colonyJSON.utf8))
        let planetTypes: [String: TypeID] = ["temperate": 11, "ice": 12, "gas": 13, "oceanic": 2014, "lava": 2015,
                                             "barren": 2016, "storm": 2017, "plasma": 2063]
        return ColonySnapshot(
            snapshotTime: planet.last_update, planetTypeID: planetTypes[planet.planet_type],
            upgradeLevel: planet.upgrade_level, planetRadius: planetRadius,
            pins: colony.pins.map { p in
                .init(pinID: p.pin_id, typeID: TypeID(rawValue: p.type_id), latitude: p.latitude, longitude: p.longitude,
                      schematicID: p.schematic_id.map { SchematicID(rawValue: $0) },
                      installTime: p.install_time, expiryTime: p.expiry_time, lastCycleStart: p.last_cycle_start,
                      contents: (p.contents ?? []).map { .init(typeID: TypeID(rawValue: $0.type_id), quantity: $0.amount) },
                      extractor: p.extractor_details.map {
                          .init(productTypeID: $0.product_type_id.map { TypeID(rawValue: $0) }, cycleTime: $0.cycle_time,
                                quantityPerCycle: $0.qty_per_cycle, headCount: $0.heads.count)
                      })
            },
            routes: colony.routes.map {
                .init(routeID: $0.route_id, sourcePinID: $0.source_pin_id, destinationPinID: $0.destination_pin_id,
                      typeID: TypeID(rawValue: $0.content_type_id), quantity: $0.quantity, waypoints: $0.waypoints ?? [])
            },
            links: colony.links.map { .init(sourcePinID: $0.source_pin_id, destinationPinID: $0.destination_pin_id, level: $0.link_level) })
    }

    func colony() throws -> Colony {
        try Colony(snapshot: Self.snapshot(), catalog: catalog)
    }

    @Test("Restore: no warnings, processors idle, extractors at cycle zero")
    func restore() throws {
        let colony = try colony()
        #expect(colony.warnings.isEmpty)
        #expect(colony.pins.count == 9)
        for pin in colony.pins {
            switch pin.role {
            case .processor(let processor):
                #expect(processor.runningCycleEnd == nil)
            case .extractor(let extractor):
                #expect(extractor.pendingCycle == 0)
                #expect(extractor.program?.cycleCount == 60)          // 5 days of 2-hour cycles
            case .storage:
                break
            }
        }
    }

    @Test("Fitting of the in-game layout matches the command center level")
    func fitting() throws {
        let fitting = try colony().fitting
        #expect(fitting.issues.isEmpty)
        #expect(fitting.cpu.total == 21315)
        #expect(fitting.power.total == 17000)
        // Client figures; they match only with the polar angle in the link length and a ceil of each link's load.
        #expect(fitting.cpu.used == 7592)
        #expect(fitting.power.used == 16743)
        // Longest link: storage -> farthest ECU.
        let longest = fitting.links.compactMap(\.length).max() ?? 0
        #expect(abs(longest - 576.2) < 0.1)
    }

    @Test("Link upgrade to G3-M5R: level 0 to 1 adds +90 CPU / +53 PG, 0 to 2 adds +201 / +112, as in the client")
    func linkUpgrade() throws {
        var snapshot = try Self.snapshot()
        let link = try #require(snapshot.links.firstIndex { $0.destinationPinID == 1020196501383 })
        let before = try Colony(snapshot: snapshot, catalog: catalog).fitting
        snapshot.links[link].level = 1
        let after = try Colony(snapshot: snapshot, catalog: catalog).fitting
        #expect(after.cpu.used - before.cpu.used == 90)
        #expect(after.power.used - before.power.used == 53)
        snapshot.links[link].level = 2
        let level2 = try Colony(snapshot: snapshot, catalog: catalog).fitting
        #expect(level2.links[link].cpu == 271)
        #expect(level2.links[link].power == 164)
    }

    @Test("G3-M5R extractor cycles match the client: yield / accumulated / per hour")
    func extractorCycles() throws {
        let colony = try colony()
        let index = try #require(colony.index(ofPinID: 1020196501383))
        guard case .extractor(let extractor) = colony[index].role, let program = extractor.program else {
            Issue.record("extractor has no program"); return
        }
        // Cycle number (from 1) -> (yield, accumulated, per hour); per hour = accumulated / elapsed hours, rounded down.
        let client: [Int: (Int, Int, Int)] = [
            1: (13336, 13336, 6668), 2: (14671, 28007, 7001), 30: (3087, 187072, 3117), 60: (2916, 263650, 2197),
        ]
        var total = 0
        for (offset, yield) in program.yields.enumerated() {
            total += yield
            guard let (expectedYield, expectedTotal, expectedHourly) = client[offset + 1] else { continue }
            #expect(yield == expectedYield)
            #expect(total == expectedTotal)
            #expect(total * 3600 / ((offset + 1) * program.cycleTime) == expectedHourly)
        }
    }

    @Test("Processor buffer holds exactly one cycle; leftover Biofuels stays in storage")
    func processorBuffer() throws {
        let colony = try colony()
        let biocells = try #require(colony.index(ofPinID: ID.biocells))
        let storage = try #require(colony.index(ofPinID: ID.storage))
        let biofuels: TypeID = 2396
        #expect(colony[biocells].contents[biofuels] == 40)
        #expect(colony[storage].contents[biofuels] == 1480)
    }

    @Test("Program simulation: nothing is wasted, all extractor output goes into production")
    func simulation() throws {
        let colony = try colony()
        var simulation = ColonySimulation(colony)
        let forecast = simulation.run(until: colony.snapshotTime.addingTimeInterval(6 * 86_400))
        #expect(!forecast.isTruncated)
        #expect(forecast.wasted.isEmpty)

        let nobleMetals: TypeID = 2270, carbonCompounds: TypeID = 2288, biocellsType: TypeID = 2329
        var totals: [TypeID: Int] = [:]
        for pinID in ID.extractors {
            let index = try #require(colony.index(ofPinID: pinID))
            guard case .extractor(let extractor) = colony[index].role, let program = extractor.program,
                  let product = extractor.productTypeID else { Issue.record("ECU \(pinID)"); continue }
            totals[product, default: 0] += program.totalYield
            #expect(forecast[index].cycles == 60)
        }
        #expect(forecast.produced[nobleMetals] == totals[nobleMetals])
        #expect(forecast.produced[carbonCompounds] == totals[carbonCompounds])

        // Mass is conserved: all produced Biocells end up on the launchpad.
        let launchpad = try #require(colony.index(ofPinID: ID.launchpad))
        #expect(simulation.colony[launchpad].contents[biocellsType]
                == colony[launchpad].contents[biocellsType] + forecast.produced[biocellsType])
        #expect(forecast.produced[biocellsType] == 350)
    }
}
