//
//  DNAImporter.swift
//  DogmaKitIO
//
//  Created by Artem Shimanski on 02.08.2026.
//
//  DNA is the one-line chat-link format:
//  `SHIP ':' HIGHS ':' MEDS ':' LOWS ':' RIGS ':' CHARGES`, each element being `typeID[_];quantity`.
//  Spec: https://developers.eveonline.com/docs/guides/fitting/
//
//  Section boundaries are not parsed: the engine derives the rack from the type's effects and the role from its
//  category, so the parser is flat.
//

import Foundation
import DogmaKit

struct DNAImporter {

    private let context: FitImporter

    init(_ context: FitImporter) {
        self.context = context
    }

    func parse(_ text: String) -> ImportResult {
        var result = ImportResult()
        guard let body = Self.unwrap(text.trimmed) else {
            result.warnings.append(.noFitsFound)
            return result
        }

        let components = body.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard let first = components.first, let shipRaw = UInt32(first.trimmed) else {
            result.warnings.append(.malformedHeader(components.first ?? ""))
            return result
        }
        let shipID = TypeID(rawValue: shipRaw)
        guard context.catalog.contains(shipID) else {
            result.warnings.append(.unknownTypeID(shipID))
            return result
        }

        var document = context.makeDocument(name: nil, ship: shipID)
        var modules: [FitDocument.Module] = []
        var drones: [FitDocument.Drone] = []
        var implants: [FitDocument.Item] = []
        var boosters: [FitDocument.Item] = []
        // DNA charges form a separate section unrelated to modules, so they are distributed after the fit is known.
        var charges: [TypeID] = []

        for component in components.dropFirst() {
            let component = component.trimmed
            guard !component.isEmpty else { continue }
            guard let entry = Self.parseEntry(component) else {
                result.warnings.append(.malformedLine(component))
                continue
            }
            guard context.catalog.contains(entry.typeID) else {
                result.warnings.append(.unknownTypeID(entry.typeID))
                continue
            }
            if entry.isUnfitted {
                // An underscore means "in cargo, not fitted".
                result.warnings.append(.droppedUnfitted(entry.typeID))
                continue
            }

            switch context.placement(of: entry.typeID) {
            case .module:
                // A module quantity means that many identical modules, not a stack.
                for _ in 0..<max(1, entry.quantity) {
                    modules.append(.init(type: entry.typeID))
                }
            case .drone:
                drones.append(.init(type: entry.typeID,
                                    count: UInt8(clamping: max(1, entry.quantity)),
                                    active: true))
            case .charge:
                charges.append(entry.typeID)
            case .implant:
                implants.append(.init(entry.typeID))
            case .booster:
                boosters.append(.init(entry.typeID))
            case .cargo, .none:
                result.warnings.append(.droppedCargo(entry.typeID, quantity: entry.quantity))
            }
        }

        // A charge goes to every empty module that accepts it: DNA does not bind a charge to a module,
        // and the quantity counts ammo units, not loaded guns.
        for chargeID in charges {
            var bound = false
            for index in modules.indices where modules[index].charge == nil {
                guard context.catalog.canLoad(chargeID, into: modules[index].type) else { continue }
                modules[index].charge = .init(chargeID)
                bound = true
            }
            if !bound {
                result.warnings.append(.unboundCharge(chargeID))
            }
        }

        document.pilots[0].implants = implants
        document.pilots[0].boosters = boosters
        document.pilots[0].ship?.modules = modules
        document.pilots[0].ship?.drones = drones
        result.documents.append(document)
        return result
    }

    // MARK: - Parsing

    /// Strips the chat-link wrapper `<url=fitting:...>Name</url>` if present.
    private static func unwrap(_ text: String) -> String? {
        guard let range = text.range(of: "fitting:") else {
            return text.isEmpty ? nil : text
        }
        let tail = text[range.upperBound...]
        guard let end = tail.firstIndex(of: ">") else { return String(tail) }
        return String(tail[tail.startIndex..<end])
    }

    private struct Entry {
        var typeID: TypeID
        var quantity: Int
        var isUnfitted: Bool
    }

    /// `12345;2`, `12345_;1` or a bare `12345` (as subsystems are written).
    private static func parseEntry(_ component: String) -> Entry? {
        var idPart = component
        var quantity = 1
        if let semicolon = component.firstIndex(of: ";") {
            idPart = String(component[component.startIndex..<semicolon])
            let tail = component[component.index(after: semicolon)...].trimmed
            quantity = Int(tail) ?? 1
        }
        var isUnfitted = false
        if idPart.hasSuffix("_") {
            isUnfitted = true
            idPart.removeLast()
        }
        guard let raw = UInt32(idPart.trimmed) else { return nil }
        return Entry(typeID: TypeID(rawValue: raw), quantity: quantity, isUnfitted: isUnfitted)
    }
}
