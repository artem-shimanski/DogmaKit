//
//  PlanetaryCatalogTests.swift
//  DogmaKit
//
//  Planetary production data (`planetary.bin`) as imported from the SDE, and the invariants
//  the colony simulation relies on. Numbers match the current SDE; if CCP changes them,
//  these tests should fail.
//

import Foundation
import Testing
import DogmaText
@testable import DogmaPlanetary

@Suite("Planetary catalog")
struct PlanetaryCatalogTests {

    let catalog: PlanetaryCatalog

    init() throws {
        catalog = try PlanetaryCatalog.bundled()
    }

    // MARK: - Schematics

    @Test("68 schematics, each with one output and sorted inputs")
    func schematicsShape() throws {
        let ids = catalog.schematicIDs
        #expect(ids.count == 68)
        for id in ids {
            let schematic = try #require(catalog.schematic(id))
            #expect(schematic.id == id)
            #expect(schematic.output.quantity > 0)
            #expect((1...3).contains(schematic.inputs.count))
            let inputIDs = schematic.inputs.map(\.typeID.rawValue)
            #expect(inputIDs == inputIDs.sorted(), "inputs of \(id) are not sorted")
            #expect(Set(inputIDs).count == inputIDs.count)
            #expect(schematic.inputs.allSatisfy { $0.quantity > 0 })
        }
    }

    @Test("Cycle time and tier: P1 takes 30 minutes, the rest an hour; inputs are always a lower tier than the output")
    func schematicTiers() throws {
        var countByTier: [DogmaPlanetaryData.Tier: Int] = [:]
        for id in catalog.schematicIDs {
            let schematic = try #require(catalog.schematic(id))
            let output = try #require(catalog.commodity(schematic.output.typeID))
            countByTier[output.tier, default: 0] += 1
            #expect(output.tier != .p0)
            #expect(schematic.cycleTime == (output.tier == .p1 ? 1800 : 3600))
            for input in schematic.inputs {
                let commodity = try #require(catalog.commodity(input.typeID))
                #expect(commodity.tier < output.tier)
            }
        }
        #expect(countByTier == [.p1: 15, .p2: 24, .p3: 21, .p4: 8])
    }

    @Test("Schematic processors are processor pins; P4 only on Barren and Temperate")
    func schematicProcessors() throws {
        for id in catalog.schematicIDs {
            let schematic = try #require(catalog.schematic(id))
            let tier = try #require(catalog.commodity(schematic.output.typeID)).tier
            #expect(schematic.processors.count == (tier == .p4 ? 2 : 8))
            for processor in schematic.processors {
                #expect(catalog.pin(processor)?.kind == .processor)
            }
            #expect(catalog.schematics(for: schematic.processors[0]).contains { $0.id == id })
        }
    }

    @Test("A schematic is found by its output")
    func schematicByOutput() throws {
        for id in catalog.schematicIDs {
            let schematic = try #require(catalog.schematic(id))
            #expect(catalog.schematic(producing: schematic.output.typeID)?.id == id)
        }
        #expect(catalog.schematic(producing: TypeID(rawValue: 1)) == nil)
    }

    @Test("Superconductors: 40 Plasmoids + 40 Water make 5 per hour")
    func superconductors() throws {
        let schematic = try #require(catalog.schematic(.superconductors))
        #expect(schematic.cycleTime == 3600)
        #expect(schematic.output.quantity == 5)
        #expect(schematic.inputs.map(\.typeID.rawValue) == [2389, 3645])
        #expect(schematic.inputs.map(\.quantity) == [40, 40])
    }

    // MARK: - Commodities

    @Test("83 commodities, volume is determined by tier")
    func commodities() throws {
        var typeIDs = Set<TypeID>()
        for id in catalog.schematicIDs {
            let schematic = try #require(catalog.schematic(id))
            typeIDs.insert(schematic.output.typeID)
            schematic.inputs.forEach { typeIDs.insert($0.typeID) }
        }
        #expect(typeIDs.count == 83)
        let volumes: [DogmaPlanetaryData.Tier: Double] = [.p0: 0.005, .p1: 0.19, .p2: 0.75, .p3: 3, .p4: 50]
        for typeID in typeIDs {
            let commodity = try #require(catalog.commodity(typeID))
            #expect(commodity.volume == volumes[commodity.tier])
        }
    }

    // MARK: - Pins

    @Test("Pins: one of each kind per planet, except processors")
    func pins() throws {
        var kindsByPlanet: [TypeID: [DogmaPlanetaryData.PinKind: Int]] = [:]
        for id in catalog.schematicIDs {
            for processor in try #require(catalog.schematic(id)).processors {
                let pin = try #require(catalog.pin(processor))
                #expect(pin.capacity == 0)
                #expect(pin.cpuLoad > 0 && pin.powerLoad > 0)
            }
        }
        for typeID in Self.planetPins {
            let pin = try #require(catalog.pin(typeID), "pin \(typeID.rawValue)")
            kindsByPlanet[pin.planetTypeID, default: [:]][pin.kind, default: 0] += 1
            switch pin.kind {
            case .commandCenter:
                #expect(pin.capacity == 500)
                #expect(pin.cpuOutput == 1675 && pin.powerOutput == 6000)
            case .storage:
                #expect(pin.capacity == 12000)
            case .launchpad:
                #expect(pin.capacity == 10000)
            case .extractor:
                #expect(pin.capacity == 0)
                #expect(pin.extractorHeadCPU == 110 && pin.extractorHeadPower == 550)
            case .processor:
                break
            }
        }
        #expect(kindsByPlanet[TypeID(rawValue: 2016)] == [.commandCenter: 1, .storage: 1, .launchpad: 1, .extractor: 1])
    }

    /// Barren: Command Center, Storage Facility, Launchpad, Extractor Control Unit.
    static let planetPins: [TypeID] = [2524, 2541, 2544, 2848]

    @Test("Legacy extractors and unpublished command centers are excluded")
    func legacyPinsExcluded() {
        #expect(catalog.pin(TypeID(rawValue: 2129)) == nil)   // Limited Barren Command Center
        #expect(catalog.pin(TypeID(rawValue: 2409)) == nil)   // Barren Aqueous Liquid Extractor (group 1026)
    }

    // MARK: - Planner

    @Test("Command center levels 0 to 5 are assembled from legacy types")
    func commandCenterLevels() {
        #expect(catalog.commandCenterLevelCount == 6)
        let expected: [(Double, Double)] = [(1675, 6000), (7057, 9000), (12136, 12000),
                                            (17215, 15000), (21315, 17000), (25415, 19000)]
        for (level, (cpu, power)) in expected.enumerated() {
            #expect(catalog.commandCenter(level: level) == .init(cpu: cpu, power: power))
        }
        #expect(catalog.commandCenter(level: 6) == nil)
        #expect(catalog.commandCenter(level: -1) == nil)
    }

    @Test("Link and extractor constants")
    func linkAndExtractor() {
        let link = catalog.link
        #expect(link.cpuLoad == 15 && link.powerLoad == 10)
        #expect(link.cpuLoadPerKm == 0.2 && link.powerLoadPerKm == 0.15)
        #expect(link.cpuLoadLevelModifier == 1.4 && link.powerLoadLevelModifier == 1.2)
        #expect(link.logisticalCapacity == 1250)
        #expect(catalog.extractor.decayFactor == 0.012)
        #expect(catalog.extractor.noiseFactor == 0.8)
    }

    // MARK: - Names

    @Test("Schematic names are in the text catalog")
    func schematicNames() throws {
        let text = try TextCatalog.english()
        #expect(text.name(of: SchematicID.superconductors) == "Superconductors")
        for id in catalog.schematicIDs {
            #expect(text.name(of: id) != nil)
        }
    }
}
