//
//  XMLExporter.swift
//  DogmaKitIO
//
//  Writes the game's fit export file. Modules carry their exact socket (`low slot 2`), drones and fighters go to
//  their bays, charges to the cargo, as the game does. Implants, boosters, states and mutations have no place in
//  the format.
//

#if os(WASI)
import FoundationEssentials
#else
import Foundation
#endif
import DogmaKit

struct XMLExporter {

    private let context: FitExporter

    init(_ context: FitExporter) {
        self.context = context
    }

    /// Rack names in the order the game writes them.
    private static let racks: [(slot: Entity.Module.Slot, name: String)] = [
        (.low, "low slot"),
        (.med, "med slot"),
        (.hi, "hi slot"),
        (.rig, "rig slot"),
        (.subsystem, "subsystem slot"),
        (.service, "service slot"),
        (.mode, "mode"),
    ]

    func write(_ fits: [FitExporter.Layout]) -> ExportResult {
        var result = ExportResult()
        var lines = [#"<?xml version="1.0" ?>"#, "<fittings>"]
        for fit in fits {
            lines += write(fit, warnings: &result.warnings)
        }
        lines.append("</fittings>")
        result.text = lines.joined(separator: "\n")
        return result
    }

    private func write(_ fit: FitExporter.Layout, warnings: inout [ExportWarning]) -> [String] {
        guard let shipName = name(of: fit.ship, warnings: &warnings) else { return [] }

        var lines = [
            #"  <fitting name="\#(Self.escaped(fit.name ?? shipName))">"#,
            #"    <description value=""/>"#,
            #"    <shipType value="\#(Self.escaped(shipName))"/>"#,
        ]
        func hardware(_ slot: String, _ type: TypeID, quantity: Int? = nil) {
            guard let name = name(of: type, warnings: &warnings) else { return }
            let qty = quantity.map { #"qty="\#($0)" "# } ?? ""
            lines.append(#"    <hardware \#(qty)slot="\#(slot)" type="\#(Self.escaped(name))"/>"#)
        }

        for (slot, rackName) in Self.racks {
            for (socket, module) in (fit.racks[slot] ?? []).enumerated() {
                guard let module else { continue }
                if module.mutation != nil { warnings.append(.droppedMutation(module.type)) }
                hardware("\(rackName) \(socket)", module.type)
            }
        }
        for drone in fit.drones {
            if drone.mutation != nil { warnings.append(.droppedMutation(drone.type)) }
            let bay = context.catalog.categoryID(of: drone.type) == .fighter ? "fighter bay" : "drone bay"
            hardware(bay, drone.type, quantity: context.count(of: drone))
        }
        for charge in context.charges(of: fit) {
            hardware("cargo", charge.type, quantity: charge.count)
        }
        warnings += (fit.implants + fit.boosters).map { .unsupportedItem($0.type) }

        lines.append("  </fitting>")
        return lines
    }

    private func name(of typeID: TypeID, warnings: inout [ExportWarning]) -> String? {
        guard let name = context.names.name(of: typeID) else {
            warnings.append(.unnamedType(typeID))
            return nil
        }
        return name
    }

    private static func escaped(_ text: String) -> String {
        var result = ""
        for character in text {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&apos;"
            default: result.append(character)
            }
        }
        return result
    }
}
