//
//  FitExporter.swift
//  DogmaKitIO
//

import Foundation
import DogmaKit

/// Exports the native `FitDocument` to public formats; the reverse of `FitImporter`.
///
/// Every pilot with a ship becomes one fit. What the formats cannot hold is dropped: skills, targets and the
/// environment always, everything else as reported in `ExportResult.warnings`.
///
/// ```swift
/// let document = await engine.export()
/// let exporter = try FitExporter(names: TextCatalog.english())
/// let eft = exporter.export(document, as: .eft).text
/// ```
public struct FitExporter: Sendable {

    public typealias Format = FitImporter.Format

    /// Type names for EFT and XML, internal attribute names for EFT mutation rolls.
    public let names: any NameCatalog
    public let catalog: TypeCatalog

    public init(names: any NameCatalog, catalog: TypeCatalog) {
        self.names = names
        self.catalog = catalog
    }

    public init(names: any NameCatalog) throws {
        self.init(names: names, catalog: try TypeCatalog())
    }

    public func export(_ document: FitDocument, as format: Format) -> ExportResult {
        var warnings: [ExportWarning] = []
        var fits: [Layout] = []
        for (index, pilot) in document.pilots.enumerated() {
            guard let ship = pilot.ship else {
                warnings.append(.noShip(pilot: index))
                continue
            }
            fits.append(layout(of: ship, pilot: pilot, name: pilot.name ?? document.name))
        }

        var result: ExportResult
        switch format {
        case .eft: result = EFTExporter(self).write(fits)
        case .dna: result = DNAExporter(self).write(fits)
        case .xml: result = XMLExporter(self).write(fits)
        }
        result.warnings.insert(contentsOf: warnings, at: 0)
        return result
    }

    // MARK: - Shared by writers

    /// A fit with modules placed into racks, the common input of all writers.
    struct Layout {
        var name: String?
        var ship: TypeID
        /// Modules by rack, in socket order; `nil` is an empty socket between modules.
        var racks: [Entity.Module.Slot: [FitDocument.Module?]]
        var drones: [FitDocument.Drone]
        var implants: [FitDocument.Item]
        var boosters: [FitDocument.Item]
    }

    /// Replays the document's socket rule: a module without `socket` takes the socket after the previous module of
    /// its rack. Only gaps between modules are kept; the formats need nothing past the last module.
    private func layout(of ship: FitDocument.Ship, pilot: FitDocument.Pilot, name: String?) -> Layout {
        var racks: [Entity.Module.Slot: [FitDocument.Module?]] = [:]
        for module in ship.modules {
            guard let slot = catalog.slot(of: module.type) else { continue }
            var rack = racks[slot, default: []]
            let socket = module.socket ?? rack.count
            if socket >= rack.count {
                rack.append(contentsOf: repeatElement(nil, count: socket - rack.count + 1))
            }
            rack[socket] = module
            racks[slot] = rack
        }
        return Layout(name: name,
                      ship: ship.type,
                      racks: racks,
                      drones: ship.drones,
                      implants: pilot.implants,
                      boosters: pilot.boosters)
    }

    /// Stack size of a drone entry; `nil` in the document means a full squadron for fighters and one drone otherwise.
    func count(of drone: FitDocument.Drone) -> Int {
        if let count = drone.count { return Int(count) }
        if catalog.categoryID(of: drone.type) == .fighter {
            return Int(catalog.attribute(.fighterSquadronMaxSize, of: drone.type) ?? 1)
        }
        return 1
    }

    /// Charges grouped by type in order of first appearance, with the number of modules loaded with each.
    func charges(of fit: Layout) -> [(type: TypeID, count: Int)] {
        var result: [(type: TypeID, count: Int)] = []
        for slot in Entity.Module.Slot.allCases {
            for case let module? in fit.racks[slot] ?? [] {
                guard let charge = module.charge?.type else { continue }
                if let index = result.firstIndex(where: { $0.type == charge }) {
                    result[index].count += 1
                } else {
                    result.append((charge, 1))
                }
            }
        }
        return result
    }
}
