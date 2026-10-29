//
//  ImportTests.swift
//  DogmaKitIO
//
//  Import of public formats (EFT / DNA / in-game XML) into `FitDocument`.
//
//  The name resolver is a test double: names are localized and not in `sde.bin`, so the
//  mapping always comes from outside. TypeIDs come from generated constants.
//

import Foundation
import Testing
import DogmaKit
// A plain import, not @testable: checks that the public surface is enough for a consumer.
import DogmaKitIO

@Suite("Import")
struct ImportTests {

    private static let resolver = DictionaryTypeResolver(
        types: [
            "Rifter": .rifter,
            "Rupture": .rupture,
            "200mm AutoCannon II": ._200mmAutoCannonII,
            "425mm AutoCannon II": ._425mmAutoCannonII,
            "Damage Control II": .damageControlII,
            "Stasis Webifier II": .stasisWebifierII,
            "50MN Microwarpdrive I": ._50MNMicrowarpdriveI,
            "Fusion S": .fusionS,
            "Fusion L": .fusionL,
            "Hobgoblin II": .hobgoblinII,
            "Limited Ocular Filter": .limitedOcularFilter,
            "Unstable 50MN Microwarpdrive Mutaplasmid": .unstable50MNMicrowarpdriveMutaplasmid,
        ],
        attributes: ["cpu": .cpu, "speedFactor": .speedFactor])

    /// A resolver without attributes, for a consumer that does not need mutations.
    private static let namesOnly = DictionaryTypeResolver(
        types: [
            "Rifter": .rifter,
            "50MN Microwarpdrive I": ._50MNMicrowarpdriveI,
            "Unstable 50MN Microwarpdrive Mutaplasmid": .unstable50MNMicrowarpdriveMutaplasmid,
        ])

    private func importer(_ resolver: any TypeResolver = ImportTests.resolver) throws -> FitImporter {
        try FitImporter(resolver: resolver)
    }

    // MARK: - EFT

    private static let eft = """
    [Rifter, Autocannon brawl]
    Damage Control II
    [Empty Low slot]
    Damage Control II

    Stasis Webifier II
    50MN Microwarpdrive I

    200mm AutoCannon II, Fusion S
    200mm AutoCannon II, Fusion S /offline

    Hobgoblin II x5

    Limited Ocular Filter
    """

    @Test("EFT: a drone line without a count is one drone")
    func eftDroneWithoutCount() throws {
        let result = try importer().load("[Rifter, Fit]\n\nHobgoblin II\n", as: .eft)
        let ship = try #require(result.documents.first?.pilots.first?.ship)
        #expect(ship.drones.map(\.type) == [.hobgoblinII])
        #expect(ship.drones.first?.count == 1)
    }

    @Test("EFT: hull, name, modules, charges and drones")
    func eftBasics() throws {
        let result = try importer().load(Self.eft, as: .eft)
        let document = try #require(result.documents.first)
        let ship = try #require(document.pilots.first?.ship)

        #expect(document.name == "Autocannon brawl")
        #expect(ship.type == .rifter)
        #expect(ship.modules.count == 6)
        #expect(ship.drones.map(\.type) == [.hobgoblinII])
        #expect(ship.drones.first?.count == 5)
        #expect(document.pilots.first?.implants.map(\.type) == [.limitedOcularFilter])
        #expect(result.warnings.isEmpty)
    }

    @Test("EFT: charge and /offline are read from the same line")
    func eftChargeAndState() throws {
        let result = try importer().load(Self.eft, as: .eft)
        let guns = try #require(result.documents.first?.pilots.first?.ship?.modules)
            .filter { $0.type == ._200mmAutoCannonII }

        #expect(guns.count == 2)
        #expect(guns.allSatisfy { $0.charge?.type == .fusionS })
        #expect(guns[0].state == nil)          // default is active
        #expect(guns[1].state == .offline)
    }

    @Test("EFT: an [Empty ... slot] line becomes a gap in the rack")
    func eftEmptySlotBecomesGap() throws {
        let result = try importer().load(Self.eft, as: .eft)
        let lows = try #require(result.documents.first?.pilots.first?.ship?.modules)
            .filter { $0.type == .damageControlII }

        #expect(lows.count == 2)
        #expect(lows[0].socket == 0)
        // The stub took socket 1, so the second module must land in socket 2;
        // otherwise overheating is computed against a different rack layout.
        #expect(lows[1].socket == 2)
    }

    @Test("EFT: sections without stubs omit sockets")
    func eftWithoutGapsOmitsSockets() throws {
        let text = """
        [Rifter, Plain]
        Damage Control II
        Damage Control II
        """
        let result = try importer().load(text, as: .eft)
        let modules = try #require(result.documents.first?.pilots.first?.ship?.modules)
        #expect(modules.allSatisfy { $0.socket == nil })
    }

    @Test("EFT: several fits in one text")
    func eftMultipleFits() throws {
        let text = Self.eft + "\n\n[Rupture, Second]\n425mm AutoCannon II, Fusion L\n"
        let result = try importer().load(text, as: .eft)

        #expect(result.documents.count == 2)
        #expect(result.documents.last?.name == "Second")
        #expect(result.documents.last?.pilots.first?.ship?.type == .rupture)
    }

    @Test("EFT: an unknown name gives a warning, not a failure")
    func eftUnknownTypeWarns() throws {
        let text = """
        [Rifter, Broken]
        Damage Control II
        Totally Not A Module
        """
        let result = try importer().load(text, as: .eft)
        #expect(result.documents.first?.pilots.first?.ship?.modules.count == 1)
        #expect(result.warnings == [.unknownType("Totally Not A Module")])
    }

    // MARK: - EFT: mutations

    private static let mutatedEFT = """
    [Rifter, Mutated]
    50MN Microwarpdrive I [1]


    [1] 50MN Microwarpdrive I
      Unstable 50MN Microwarpdrive Mutaplasmid
      cpu 45.0, speedFactor 520.0
    """

    @Test("EFT: a mutation block becomes a mutaplasmid and rolls")
    func eftMutationBlock() throws {
        let result = try importer().load(Self.mutatedEFT, as: .eft)
        let module = try #require(result.documents.first?.pilots.first?.ship?.modules.first)
        let mutation = try #require(module.mutation)

        // A mutated module keeps its BASE type in the document.
        #expect(module.type == ._50MNMicrowarpdriveI)
        #expect(mutation.mutaplasmid.type == .unstable50MNMicrowarpdriveMutaplasmid)
        #expect(mutation.rolls.count == 2)
        #expect(mutation.rolls.contains { $0.attribute == .cpu && $0.value == 45 })
        #expect(result.warnings.isEmpty)
    }

    @Test("EFT: without an attribute resolver the mutation stays and the rolls are dropped")
    func eftMutationWithoutAttributeResolver() throws {
        let result = try importer(Self.namesOnly).load(Self.mutatedEFT, as: .eft)
        let mutation = try #require(result.documents.first?.pilots.first?.ship?.modules.first?.mutation)

        #expect(mutation.mutaplasmid.type == .unstable50MNMicrowarpdriveMutaplasmid)
        #expect(mutation.rolls.isEmpty)
        #expect(result.warnings.contains(.mutationRollsDropped(._50MNMicrowarpdriveI)))
    }

    @Test("EFT: mutation block lines do not end up in the fit")
    func eftMutationBlockIsConsumed() throws {
        let result = try importer().load(Self.mutatedEFT, as: .eft)
        let ship = try #require(result.documents.first?.pilots.first?.ship)
        #expect(ship.modules.count == 1)
        #expect(ship.drones.isEmpty)
    }

    // MARK: - DNA

    @Test("DNA: modules by count, drones as a stack, charge by compatibility")
    func dnaBasics() throws {
        let dna = [
            "\(TypeID.rifter.rawValue)",
            "\(TypeID._200mmAutoCannonII.rawValue);2",
            "\(TypeID.damageControlII.rawValue);1",
            "\(TypeID.hobgoblinII.rawValue);3",
            "\(TypeID.fusionS.rawValue);100",
            "",
            "",
        ].joined(separator: ":")

        let result = try importer().load(dna, as: .dna)
        let ship = try #require(result.documents.first?.pilots.first?.ship)

        #expect(ship.type == .rifter)
        // `;2` on a module means two identical modules, not a stack.
        #expect(ship.modules.filter { $0.type == ._200mmAutoCannonII }.count == 2)
        #expect(ship.drones.first?.count == 3)
        // The charge goes to every gun that accepts it: DNA has no explicit binding.
        #expect(ship.modules.filter { $0.charge?.type == .fusionS }.count == 2)
        #expect(ship.modules.first { $0.type == .damageControlII }?.charge == nil)
    }

    @Test("DNA: an underscore means not fitted")
    func dnaUnfittedIsDropped() throws {
        let dna = "\(TypeID.rifter.rawValue):\(TypeID.damageControlII.rawValue)_;1::"
        let result = try importer().load(dna, as: .dna)

        #expect(result.documents.first?.pilots.first?.ship?.modules.isEmpty == true)
        #expect(result.warnings == [.droppedUnfitted(.damageControlII)])
    }

    @Test("DNA: the chat link wrapper is stripped")
    func dnaChatLink() throws {
        let dna = "<url=fitting:\(TypeID.rifter.rawValue):\(TypeID.damageControlII.rawValue);1::>Fit</url>"
        let result = try importer().load(dna, as: .dna)

        #expect(result.documents.first?.pilots.first?.ship?.type == .rifter)
        #expect(result.documents.first?.pilots.first?.ship?.modules.count == 1)
        #expect(result.documents.first?.name == "Fit")
    }

    @Test("DNA: the link as pasted from chat, without a name, or as a bare target", arguments: [
        ("[ 2026.10.26 12:00:00 ] Pilot > <url=fitting:587:2048;1::>Fit</url>\n", "Fit"),
        ("\n  <url=fitting:587:2048;1::></url>  \n", nil),
        ("fitting:587:2048;1::", nil),
        (" 587:2048;1::\n", nil),
    ] as [(String, String?)])
    func dnaLinkForms(text: String, name: String?) throws {
        #expect(FitImporter.detect(text) == .dna)
        let result = try importer().load(text)
        #expect(result.warnings.isEmpty, "\(result.warnings)")
        let document = try #require(result.documents.first)
        #expect(document.name == name)
        #expect(document.pilots.first?.ship?.type == .rifter)
        #expect(document.pilots.first?.ship?.modules.map(\.type) == [.damageControlII])
    }

    // MARK: - XML

    private static let xml = """
    <?xml version="1.0" ?>
    <fittings>
        <fitting name="Autocannon brawl">
            <description value=""/>
            <shipType value="Rifter"/>
            <hardware slot="low slot 0" type="Damage Control II"/>
            <hardware slot="low slot 2" type="Damage Control II"/>
            <hardware slot="hi slot 0" type="200mm AutoCannon II"/>
            <hardware qty="5" slot="drone bay" type="Hobgoblin II"/>
            <hardware qty="100" slot="cargo" type="Fusion S"/>
        </fitting>
        <fitting name="Second">
            <shipType value="Rupture"/>
            <hardware slot="hi slot 0" type="425mm AutoCannon II"/>
        </fitting>
    </fittings>
    """

    @Test("XML: several fits, slots and drones")
    func xmlBasics() throws {
        let result = try importer().load(Self.xml, as: .xml)

        #expect(result.documents.count == 2)
        let first = try #require(result.documents.first?.pilots.first?.ship)
        #expect(first.type == .rifter)
        #expect(first.modules.count == 3)
        #expect(first.drones.first?.count == 5)
        #expect(result.documents.last?.pilots.first?.ship?.type == .rupture)
    }

    @Test("XML: the slot number gives an exact gap in the rack")
    func xmlSocketGap() throws {
        let result = try importer().load(Self.xml, as: .xml)
        let lows = try #require(result.documents.first?.pilots.first?.ship?.modules)
            .filter { $0.type == .damageControlII }

        #expect(lows.count == 2)
        #expect(lows[0].socket == nil)   // equals the expected 0
        #expect(lows[1].socket == 2)
    }

    @Test("XML: cargo is dropped with a warning")
    func xmlCargoIsDropped() throws {
        let result = try importer().load(Self.xml, as: .xml)
        #expect(result.warnings == [.droppedCargo(.fusionS, quantity: 100)])
    }

    // MARK: - Auto-detection

    @Test("The format is detected from the first line")
    func formatDetection() {
        #expect(FitImporter.detect(Self.eft) == .eft)
        #expect(FitImporter.detect(Self.xml) == .xml)
        #expect(FitImporter.detect("587:2048;1::") == .dna)
        // A chat link starts with `<` but is DNA, not XML.
        #expect(FitImporter.detect("<url=fitting:587:2048;1::>Fit</url>") == .dna)
        // An EFT fit whose name mentions `fitting:` stays EFT.
        #expect(FitImporter.detect("[Rifter, PvP fitting: kite]\nDamage Control II") == .eft)
        #expect(FitImporter.detect("   ") == nil)
    }

    // MARK: - End to end

    @Test("EFT reaches the engine and is evaluated")
    func endToEnd() async throws {
        let result = try importer().load(Self.eft, as: .eft)
        let document = try #require(result.documents.first)

        let engine = DogmaEngine()
        let warnings = try await engine.load(document, strict: true)
        #expect(warnings.isEmpty)

        let (hullType, dps) = await engine.evaluate { stats -> (TypeID, Double) in
            let hull = stats[PilotID(1).hull]
            let damage = hull.dps()
            return (hull.typeID, damage.em + damage.thermal + damage.kinetic + damage.explosive)
        }
        #expect(hullType == .rifter)
        #expect(dps > 0)
    }
}
