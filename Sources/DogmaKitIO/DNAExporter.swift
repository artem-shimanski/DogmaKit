//
//  DNAExporter.swift
//  DogmaKitIO
//
//  Writes `SHIP:SUBSYSTEMS:HIGHS:MEDS:LOWS:RIGS:…:DRONES:CHARGES::`, each element `typeID;quantity`, identical types
//  merged. One line per fit. The format has no names, states, sockets, implants, boosters or mutations.
//

import Foundation
import DogmaKit

struct DNAExporter {

    private let context: FitExporter

    init(_ context: FitExporter) {
        self.context = context
    }

    /// Subsystems first: the game derives the slot layout of a strategic cruiser from them.
    private static let rackOrder: [Entity.Module.Slot] = [.subsystem, .hi, .med, .low, .rig, .service, .mode]

    func write(_ fits: [FitExporter.Layout]) -> ExportResult {
        var result = ExportResult()
        result.text = fits.map { write($0, warnings: &result.warnings) }.joined(separator: "\n")
        return result
    }

    private func write(_ fit: FitExporter.Layout, warnings: inout [ExportWarning]) -> String {
        var entries: [(type: TypeID, count: Int)] = []
        func add(_ type: TypeID, _ count: Int) {
            if let index = entries.firstIndex(where: { $0.type == type }) {
                entries[index].count += count
            } else {
                entries.append((type, count))
            }
        }

        for slot in Self.rackOrder {
            for case let module? in fit.racks[slot] ?? [] {
                if module.mutation != nil { warnings.append(.droppedMutation(module.type)) }
                add(module.type, 1)
            }
        }
        for drone in fit.drones {
            if drone.mutation != nil { warnings.append(.droppedMutation(drone.type)) }
            add(drone.type, context.count(of: drone))
        }
        for charge in context.charges(of: fit) {
            add(charge.type, charge.count)
        }
        warnings += (fit.implants + fit.boosters).map { .unsupportedItem($0.type) }

        let items = entries.map { "\($0.type.rawValue);\($0.count)" }
        return ([String(fit.ship.rawValue)] + items).joined(separator: ":") + "::"
    }
}
