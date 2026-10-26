//
//  XMLImporter.swift
//  DogmaKitIO
//
//  Created by Artem Shimanski on 02.08.2026.
//
//  XML is the fit export file format of the game, holding several fits in one document:
//
//  ```xml
//  <fittings>
//    <fitting name="...">
//      <shipType value="Heron Navy Issue"/>
//      <hardware slot="low slot 0" type="Inertial Stabilizers II"/>
//      <hardware qty="8" slot="cargo" type="Sisters Core Scanner Probe"/>
//    </fitting>
//  </fittings>
//  ```
//
//  Unlike EFT, the slot is explicit, so gaps in racks are restored exactly.
//

#if os(WASI)
import FoundationEssentials
#else
import Foundation
#endif
#if canImport(FoundationXML) && !os(WASI)
// Outside Apple platforms `XMLParser` lives in a separate module.
import FoundationXML
#endif
import DogmaKit

#if os(WASI)
/// `XMLParser` exists only in full Foundation, which a WebAssembly build leaves out; XML finds no fits there.
struct XMLImporter {

    init(_ context: FitImporter) {}

    func parse(_ text: String) -> ImportResult {
        ImportResult(warnings: [.noFitsFound])
    }
}
#else
struct XMLImporter {

    private let context: FitImporter

    init(_ context: FitImporter) {
        self.context = context
    }

    func parse(_ text: String) -> ImportResult {
        parse(Data(text.utf8))
    }

    func parse(_ data: Data) -> ImportResult {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), !delegate.fittings.isEmpty else {
            return ImportResult(warnings: [.noFitsFound])
        }
        var result = ImportResult()
        for fitting in delegate.fittings {
            build(fitting, into: &result)
        }
        return result
    }

    // MARK: - Building the document

    private func build(_ fitting: Fitting, into result: inout ImportResult) {
        guard let shipName = fitting.shipType else {
            result.warnings.append(.malformedHeader(fitting.name ?? ""))
            return
        }
        guard let shipID = context.resolver.typeID(named: shipName) else {
            result.warnings.append(.unknownType(shipName))
            return
        }

        var document = context.makeDocument(name: fitting.name, ship: shipID)
        // Modules accumulate per rack: a socket number is meaningful only within a rack.
        var racks: [String: [(index: Int, typeID: TypeID)]] = [:]
        var drones: [FitDocument.Drone] = []
        var implants: [FitDocument.Item] = []
        var boosters: [FitDocument.Item] = []

        for hardware in fitting.hardware {
            guard let typeID = context.resolver.typeID(named: hardware.type) else {
                result.warnings.append(.unknownType(hardware.type))
                continue
            }
            let placement = context.placement(of: typeID)
            let slot = Self.parseSlot(hardware.slot)

            // The cargo section may contain anything (drones and charges included) but the model has no cargo, so drop it right away.
            if slot?.rack == "cargo" {
                result.warnings.append(.droppedCargo(typeID, quantity: hardware.quantity))
                continue
            }

            switch placement {
            case .module:
                guard let slot else {
                    result.warnings.append(.malformedLine(hardware.slot))
                    continue
                }
                racks[slot.rack, default: []].append((slot.index, typeID))
            case .drone:
                drones.append(.init(type: typeID,
                                    count: UInt8(clamping: max(1, hardware.quantity)),
                                    active: true))
            case .implant:
                implants.append(.init(typeID))
            case .booster:
                boosters.append(.init(typeID))
            case .charge, .cargo, .none:
                result.warnings.append(.droppedCargo(typeID, quantity: hardware.quantity))
            }
        }

        var modules: [FitDocument.Module] = []
        for rack in Self.rackOrder(of: racks.keys) {
            var expected = 0
            for entry in racks[rack]!.sorted(by: { $0.index < $1.index }) {
                var module = FitDocument.Module(type: entry.typeID)
                if entry.index != expected { module.socket = entry.index }
                expected = entry.index + 1
                modules.append(module)
            }
        }

        document.pilots[0].implants = implants
        document.pilots[0].boosters = boosters
        document.pilots[0].ship?.modules = modules
        document.pilots[0].ship?.drones = drones
        result.documents.append(document)
    }

    /// Rack order in the document matches the native export (`Entity.Module.Slot.allCases`), not alphabetical, so
    /// documents diff cleanly. Unknown rack names go last, alphabetically.
    private static let rackNames = ["hi slot", "med slot", "low slot", "rig slot",
                                    "subsystem slot", "mode", "service slot"]

    private static func rackOrder(of keys: some Collection<String>) -> [String] {
        keys.sorted { lhs, rhs in
            let l = rackNames.firstIndex(of: lhs) ?? rackNames.count
            let r = rackNames.firstIndex(of: rhs) ?? rackNames.count
            return l == r ? lhs < rhs : l < r
        }
    }

    /// `"low slot 0"` -> `("low slot", 0)`, `"cargo"` -> `("cargo", 0)`. The rack name is used only to count sockets within a rack.
    private static func parseSlot(_ slot: String) -> (rack: String, index: Int)? {
        let parts = slot.trimmed.lowercased().split(separator: " ")
        guard let last = parts.last else { return nil }
        if let index = Int(last) {
            return (parts.dropLast().joined(separator: " "), index)
        }
        return (parts.joined(separator: " "), 0)
    }

    // MARK: - XML parsing

    private struct Hardware {
        var slot: String
        var type: String
        var quantity: Int
    }

    private struct Fitting {
        var name: String?
        var shipType: String?
        var hardware: [Hardware] = []
    }

    /// `XMLParser` is streaming and delegate-based, so state lives in a class. The schema is flat (two levels), so no element stack is needed.
    private final class Delegate: NSObject, XMLParserDelegate {
        var fittings: [Fitting] = []
        private var current: Fitting?

        func parser(_ parser: XMLParser,
                    didStartElement elementName: String,
                    namespaceURI: String?,
                    qualifiedName: String?,
                    attributes: [String: String]) {
            switch elementName {
            case "fitting":
                current = Fitting(name: attributes["name"]?.trimmed)
            case "shipType":
                current?.shipType = attributes["value"]?.trimmed
            case "hardware":
                guard let type = attributes["type"]?.trimmed, !type.isEmpty else { return }
                current?.hardware.append(Hardware(slot: attributes["slot"] ?? "",
                                                  type: type,
                                                  quantity: attributes["qty"].flatMap(Int.init) ?? 1))
            default:
                break
            }
        }

        func parser(_ parser: XMLParser,
                    didEndElement elementName: String,
                    namespaceURI: String?,
                    qualifiedName: String?) {
            guard elementName == "fitting", let current else { return }
            fittings.append(current)
            self.current = nil
        }
    }
}
#endif
