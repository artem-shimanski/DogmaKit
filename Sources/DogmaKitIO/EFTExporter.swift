//
//  EFTExporter.swift
//  DogmaKitIO
//
//  Writes the game's clipboard layout: racks low, med, high, rig, subsystem (always present, possibly empty), then
//  service slots and the tactical mode, drones, implants and boosters, and finally the mutation blocks of the pyfa
//  extension. A gap between modules is written as an `[Empty … slot]` stub, which `EFTImporter` turns back into
//  sockets.
//

import Foundation
import DogmaKit

struct EFTExporter {

    private let context: FitExporter

    init(_ context: FitExporter) {
        self.context = context
    }

    /// Racks always written, in the game's order, with the names used in empty-slot stubs.
    private static let mainRacks: [(slot: Entity.Module.Slot, stub: String)] = [
        (.low, "[Empty Low slot]"),
        (.med, "[Empty Med slot]"),
        (.hi, "[Empty High slot]"),
        (.rig, "[Empty Rig slot]"),
        (.subsystem, "[Empty Subsystem slot]"),
    ]

    /// Racks written only when fitted.
    private static let extraRacks: [(slot: Entity.Module.Slot, stub: String)] = [
        (.service, "[Empty Service slot]"),
        (.mode, "[Empty Mode slot]"),
    ]

    func write(_ fits: [FitExporter.Layout]) -> ExportResult {
        var result = ExportResult()
        result.text = fits.map { write($0, warnings: &result.warnings) }.joined(separator: "\n\n")
        return result
    }

    private func write(_ fit: FitExporter.Layout, warnings: inout [ExportWarning]) -> String {
        var mutations: [(base: TypeID, mutation: FitDocument.Mutation)] = []

        func mutationReference(_ base: TypeID, _ mutation: FitDocument.Mutation?) -> String {
            guard let mutation else { return "" }
            mutations.append((base, mutation))
            return " [\(mutations.count)]"
        }

        let shipName = context.names.name(of: fit.ship)
        if shipName == nil { warnings.append(.unnamedType(fit.ship)) }
        var sections: [[String]] = []

        let racks = Self.mainRacks + Self.extraRacks.filter { !(fit.racks[$0.slot] ?? []).isEmpty }
        for (slot, stub) in racks {
            var lines: [String] = []
            for module in fit.racks[slot] ?? [] {
                guard let module else {
                    lines.append(stub)
                    continue
                }
                guard let name = name(of: module.type, warnings: &warnings) else { continue }
                var line = name
                if let charge = module.charge, let chargeName = self.name(of: charge.type, warnings: &warnings) {
                    line += ", \(chargeName)"
                }
                if module.state == .offline {
                    line += " /offline"
                }
                line += mutationReference(module.type, module.mutation)
                lines.append(line)
            }
            sections.append(lines)
        }

        // Module sections stay even when empty, the rest only when filled.
        let drones = fit.drones.compactMap { drone in
            name(of: drone.type, warnings: &warnings).map {
                "\($0) x\(context.count(of: drone))" + mutationReference(drone.type, drone.mutation)
            }
        }
        let implants = fit.implants.compactMap { name(of: $0.type, warnings: &warnings) }
        let boosters = fit.boosters.compactMap { name(of: $0.type, warnings: &warnings) }
        sections += [drones, implants, boosters].filter { !$0.isEmpty }

        var text = "[\(shipName ?? "\(fit.ship.rawValue)"), \(fit.name ?? shipName ?? "")]\n"
        text += sections.map { $0.joined(separator: "\n") }.joined(separator: "\n\n")

        for (index, entry) in mutations.enumerated() {
            text += "\n\n" + mutationBlock(index + 1, entry.base, entry.mutation, warnings: &warnings)
        }
        return text
    }

    /// `[N] Base type` / `  Mutaplasmid` / `  attribute value, …` with INTERNAL attribute names.
    private func mutationBlock(_ reference: Int,
                               _ base: TypeID,
                               _ mutation: FitDocument.Mutation,
                               warnings: inout [ExportWarning]) -> String {
        var lines = ["[\(reference)] \(context.names.name(of: base) ?? "\(base.rawValue)")"]
        lines.append("  " + (name(of: mutation.mutaplasmid.type, warnings: &warnings) ?? "\(mutation.mutaplasmid.type.rawValue)"))
        let rolls = mutation.rolls.compactMap { roll -> String? in
            guard let name = context.names.name(of: roll.attribute) else {
                warnings.append(.unnamedAttribute(roll.attribute))
                return nil
            }
            return "\(name) \(Self.format(roll.value))"
        }
        if !rolls.isEmpty {
            lines.append("  " + rolls.joined(separator: ", "))
        }
        return lines.joined(separator: "\n")
    }

    private func name(of typeID: TypeID, warnings: inout [ExportWarning]) -> String? {
        guard let name = context.names.name(of: typeID) else {
            warnings.append(.unnamedType(typeID))
            return nil
        }
        return name
    }

    /// Shortest exact representation, without a trailing `.0` on whole numbers.
    private static func format(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 {
            return String(Int64(value))
        }
        return String(value)
    }
}
