//
//  TypeCatalog.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 02.08.2026.
//

import Foundation
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
        guard let url = Bundle.module.url(forResource: "sde", withExtension: "bin") else {
            throw CocoaError(.fileNoSuchFile)
        }
        self.sde = SDE(data: try Data(contentsOf: url, options: [.mappedIfSafe]))
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
