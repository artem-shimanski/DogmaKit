//
//  TypeCatalog.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 02.08.2026.
//

#if os(WASI)
import FoundationEssentials
#else
import Foundation
#endif
import DogmaModels

/// Read-only type lookup over the SDE database that does not require an engine, e.g. for
/// format importers that need to classify raw data before a fit exists.
///
/// Type names are not included (they are localized); name-to-TypeID mapping is up to the
/// consumer, e.g. `DogmaKitIO.DictionaryTypeResolver` or `TextCatalog` from `DogmaText`.
///
/// The database is memory-mapped, so an extra instance is cheap.
public struct TypeCatalog: Sendable {
    private let sde: SDE

    public init() throws {
        self.sde = SDE(data: try SDEFile.load())
    }

    public func contains(_ typeID: TypeID) -> Bool {
        sde[typeID] != nil
    }

    public func groupID(of typeID: TypeID) -> GroupID? {
        sde[typeID]?.groupID.load()
    }

    public func categoryID(of typeID: TypeID) -> CategoryID? {
        sde[typeID]?.categoryID.load()
    }

    /// The rack a module type goes into, derived from its effects exactly as `Fit.Hull.modules.add`
    /// does. `nil` for a type that is not in the database or cannot be fitted into any slot.
    public func slot(of typeID: TypeID) -> Entity.Module.Slot? {
        guard let type = sde[typeID] else { return nil }
        return try? Entity.Module(type).slot
    }

    /// Whether a module type passes the hull's fitting restrictions (`canFitShipType*`,
    /// `canFitShipGroup*`, `fitsToShipType`). Slot and size checks are not part of it.
    public func canFit(_ typeID: TypeID, to hullID: TypeID) -> Bool {
        let sde = self.sde
        guard let type = sde[typeID], let hull = sde[hullID] else { return false }
        return type.fittingRequirements?.canFit(to: hull) ?? true
    }

    /// Type IDs of a group, sorted.
    public func typeIDs(inGroup groupID: GroupID) -> [TypeID] {
        var result: [TypeID] = []
        let decoder = sde.decoder
        decoder.decode(DogmaSDE.self).types.forEach { entry in
            if entry.value.groupID.load() == groupID {
                result.append(entry.key.load())
            }
        }
        return result.sorted { $0.rawValue < $1.rawValue }
    }

    /// Base attribute value of a type, without mutations or modifiers.
    public func attribute(_ attributeID: AttributeID, of typeID: TypeID) -> Double? {
        (sde[typeID]?.attributes[attributeID]?.load()).map(Double.init)
    }

    /// Whether a charge fits a module per SDE requirements (`chargeGroup`/`chargeSize` and
    /// `capacity`/`volume`). Same check as `Fit.Module.setCharge`, without entities.
    public func canLoad(_ chargeID: TypeID, into moduleID: TypeID) -> Bool {
        let sde = self.sde
        guard let module = sde[moduleID], let charge = sde[chargeID] else { return false }
        guard let requirements = module.chargeRequirements,
              requirements.canLoad(with: charge) else { return false }
        if let capacity = module.attributes[.capacity]?.load(),
           let volume = charge.attributes[.volume]?.load(),
           capacity < volume {
            return false
        }
        return true
    }

    /// Whether the mutaplasmid applies to this base type.
    public func isMutaplasmid(_ mutaplasmidID: TypeID, applicableTo typeID: TypeID) -> Bool {
        let sde = self.sde
        guard let mutaplasmid = sde.mutaplasmid(mutaplasmidID) else {return false}
        return mutaplasmid.applicableTypes.contains(typeID)
    }
}
