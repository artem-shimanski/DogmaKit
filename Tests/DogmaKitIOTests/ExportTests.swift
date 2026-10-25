//
//  ExportTests.swift
//  DogmaKitIO
//
//  Export of `FitDocument` to public formats (EFT / DNA / in-game XML). Every format is checked by importing the
//  text back: what the format can hold must survive the round trip, what it cannot must be reported.
//

import Foundation
import Testing
import DogmaKit
import DogmaText
// A plain import, not @testable: checks that the public surface is enough for a consumer.
import DogmaKitIO

@Suite("Export")
struct ExportTests {

    private static let names = try! TextCatalog.english()
    private static let catalog = try! TypeCatalog()
    private static let exporter = FitExporter(names: names, catalog: catalog)
    private static let importer = FitImporter(resolver: names, catalog: catalog)

    /// Rifter with a gap in the low rack, charges, an offline gun, a mutated MWD, drones, an implant and a booster.
    private static let document = FitDocument(
        name: "Autocannon brawl",
        pilots: [.init(
            skills: .init(default: 5),
            implants: [.init(.limitedOcularFilter)],
            boosters: [.init(.standardBluePillBooster)],
            ship: .init(
                type: .rifter,
                modules: [
                    .init(type: .damageControlII),
                    .init(type: .damageControlII, socket: 2),
                    .init(type: .stasisWebifierII),
                    .init(type: ._50MNMicrowarpdriveI,
                          mutation: .init(mutaplasmid: .init(.unstable50MNMicrowarpdriveMutaplasmid),
                                          rolls: [.init(attribute: .cpu, value: 52.5),
                                                  .init(attribute: .speedFactor, value: 512.25)])),
                    .init(type: ._200mmAutoCannonII, charge: .init(.fusionS)),
                    .init(type: ._200mmAutoCannonII, state: .offline, charge: .init(.fusionS)),
                ],
                drones: [.init(type: .hobgoblinII, count: 5, active: true)]))])

    // MARK: - Comparison

    /// Racks with every module at its effective socket, so documents compare regardless of how sockets are written.
    private func racks(_ ship: FitDocument.Ship) -> [Entity.Module.Slot: [TypeID?]] {
        var racks: [Entity.Module.Slot: [TypeID?]] = [:]
        for module in ship.modules {
            let slot = try! #require(Self.catalog.slot(of: module.type))
            var rack = racks[slot, default: []]
            let socket = module.socket ?? rack.count
            while rack.count <= socket { rack.append(nil) }
            rack[socket] = module.type
            racks[slot] = rack
        }
        return racks
    }

    private func export(_ document: FitDocument, as format: FitImporter.Format) -> (String, [ExportWarning]) {
        let result = Self.exporter.export(document, as: format)
        return (result.text, result.warnings)
    }

    // MARK: - EFT

    @Test("EFT keeps sockets, charges, states, mutations, drones, implants and boosters")
    func eftRoundTrip() throws {
        let (text, warnings) = export(Self.document, as: .eft)
        #expect(warnings.isEmpty)

        let result = Self.importer.load(text, as: .eft)
        #expect(result.warnings.isEmpty, "\(result.warnings)")
        let imported = try #require(result.documents.first)
        let pilot = try #require(imported.pilots.first)
        let ship = try #require(pilot.ship)
        let original = Self.document.pilots[0]

        #expect(imported.name == Self.document.name)
        #expect(ship.type == .rifter)
        #expect(racks(ship) == racks(original.ship!))
        #expect(ship.modules.map(\.charge) == original.ship!.modules.map(\.charge))
        #expect(ship.modules.map(\.state) == original.ship!.modules.map(\.state))
        #expect(ship.modules.map(\.mutation) == original.ship!.modules.map(\.mutation))
        #expect(ship.drones == original.ship!.drones)
        #expect(pilot.implants == original.implants)
        #expect(pilot.boosters == original.boosters)
    }

    /// The empty rig and subsystem racks still take their sections, hence the run of empty lines.
    @Test("EFT layout: racks low to high, stub for a gap, mutation block at the end")
    func eftLayout() {
        let (text, _) = export(Self.document, as: .eft)
        #expect(text == """
        [Rifter, Autocannon brawl]
        Damage Control II
        [Empty Low slot]
        Damage Control II

        Stasis Webifier II
        50MN Microwarpdrive I [1]

        200mm AutoCannon II, Fusion S
        200mm AutoCannon II, Fusion S /offline





        Hobgoblin II x5

        Limited Ocular Filter

        Standard Blue Pill Booster

        [1] 50MN Microwarpdrive I
          Unstable 50MN Microwarpdrive Mutaplasmid
          cpu 52.5, speedFactor 512.25
        """)
    }

    @Test("EFT: every pilot with a ship becomes a fit, a pilot without one is reported")
    func eftSeveralPilots() throws {
        var document = Self.document
        document.pilots.append(.init(name: "Tackle", ship: .init(type: .rupture)))
        document.pilots.append(.init(name: "Pod"))

        let (text, warnings) = export(document, as: .eft)
        let result = Self.importer.load(text, as: .eft)

        #expect(warnings == [.noShip(pilot: 2)])
        #expect(result.documents.map { $0.pilots.first?.ship?.type } == [.rifter, .rupture])
        #expect(result.documents.map(\.name) == ["Autocannon brawl", "Tackle"])
    }

    @Test("EFT: a fit without a name is named after the hull")
    func eftUnnamedFit() {
        let document = FitDocument(pilots: [.init(ship: .init(type: .rifter))])
        let (text, _) = export(document, as: .eft)
        #expect(text.hasPrefix("[Rifter, Rifter]"))
    }

    @Test("A type without a name is omitted and reported")
    func unnamedTypeWarns() {
        let names = DictionaryNames(types: [.rifter: "Rifter"])
        let exporter = FitExporter(names: names, catalog: Self.catalog)
        let document = FitDocument(pilots: [.init(ship: .init(type: .rifter, modules: [.init(type: .damageControlII)]))])

        let result = exporter.export(document, as: .eft)
        #expect(result.warnings == [.unnamedType(.damageControlII)])
        #expect(!result.text.contains("Damage Control"))
    }

    // MARK: - DNA

    @Test("DNA: identical types merge, charges count loaded modules, unsupported items are reported")
    func dnaLayout() {
        let (text, warnings) = export(Self.document, as: .dna)
        let entries: [(TypeID, Int)] = [
            (._200mmAutoCannonII, 2), (.stasisWebifierII, 1), (._50MNMicrowarpdriveI, 1),
            (.damageControlII, 2), (.hobgoblinII, 5), (.fusionS, 2),
        ]
        let items: [String] = entries.map { "\($0.0.rawValue);\($0.1)" }
        let expected = ([String(TypeID.rifter.rawValue)] + items).joined(separator: ":") + "::"
        #expect(text == expected)
        #expect(warnings == [.droppedMutation(._50MNMicrowarpdriveI),
                             .unsupportedItem(.limitedOcularFilter),
                             .unsupportedItem(.standardBluePillBooster)])
    }

    @Test("DNA round trip keeps modules, charges and drones")
    func dnaRoundTrip() throws {
        let (text, _) = export(Self.document, as: .dna)
        let result = Self.importer.load(text, as: .dna)
        #expect(result.warnings.isEmpty, "\(result.warnings)")
        let ship = try #require(result.documents.first?.pilots.first?.ship)
        let original = Self.document.pilots[0].ship!

        let types: [UInt32] = ship.modules.map(\.type.rawValue).sorted()
        let originalTypes: [UInt32] = original.modules.map(\.type.rawValue).sorted()
        let loaded = ship.modules.filter { $0.charge?.type == TypeID.fusionS }.count
        #expect(types == originalTypes)
        #expect(loaded == 2)
        #expect(ship.drones.map(\.type) == [.hobgoblinII])
        #expect(ship.drones.first?.count == 5)
    }

    // MARK: - XML

    @Test("XML round trip keeps exact sockets and drones; charges go to the cargo")
    func xmlRoundTrip() throws {
        let (text, warnings) = export(Self.document, as: .xml)
        #expect(warnings == [.droppedMutation(._50MNMicrowarpdriveI),
                             .unsupportedItem(.limitedOcularFilter),
                             .unsupportedItem(.standardBluePillBooster)])
        #expect(text.contains(#"<hardware slot="low slot 2" type="Damage Control II"/>"#))
        #expect(text.contains(#"<hardware qty="2" slot="cargo" type="Fusion S"/>"#))

        let result = Self.importer.load(text, as: .xml)
        // The importer drops the cargo, which is where the format keeps charges.
        #expect(result.warnings == [.droppedCargo(.fusionS, quantity: 2)])
        let imported = try #require(result.documents.first)
        let ship = try #require(imported.pilots.first?.ship)

        #expect(imported.name == Self.document.name)
        #expect(racks(ship) == racks(Self.document.pilots[0].ship!))
        #expect(ship.drones.map(\.type) == [.hobgoblinII])
        #expect(ship.drones.first?.count == 5)
    }

    @Test("XML escapes names")
    func xmlEscapesNames() {
        let document = FitDocument(name: #"Kite & "brawl" <v2>"#, pilots: [.init(ship: .init(type: .rifter))])
        let (text, _) = export(document, as: .xml)
        #expect(text.contains(#"name="Kite &amp; &quot;brawl&quot; &lt;v2&gt;""#))
        #expect(Self.importer.load(text, as: .xml).documents.first?.name == document.name)
    }

    // MARK: - From the engine

    @Test("A fit exported from the engine imports back into an equal fit")
    func engineRoundTrip() async throws {
        let engine = DogmaEngine()
        try await engine.load(Self.document)
        let exported = await engine.export()

        let text = Self.exporter.export(exported, as: .eft).text
        let reimported = try #require(Self.importer.load(text, as: .eft).documents.first)

        let other = DogmaEngine()
        try await other.load(reimported)
        let (a, b) = (await engine.evaluate { $0[PilotID(1).hull].attributes[.maxVelocity] ?? 0 },
                      await other.evaluate { $0[PilotID(1).hull].attributes[.maxVelocity] ?? 0 })
        #expect(a > 0)
        #expect(a == b)
    }
}

/// A name catalog over a dictionary, for tests that need missing names.
private struct DictionaryNames: NameCatalog {
    var types: [TypeID: String]
    func name(of id: TypeID) -> String? { types[id] }
}
