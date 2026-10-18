//
//  ImportWarning.swift
//  DogmaKitIO
//
//  Created by Artem Shimanski on 02.08.2026.
//

import DogmaKit

/// Something lost while parsing a public format. Import does not fail; it reports what it dropped.
public enum ImportWarning: Error, Sendable, Equatable {
    /// The name did not resolve to a `TypeID`; the resolver does not know it.
    case unknownType(String)
    /// The line has a `TypeID` that is not in `sde.bin` (DNA, old fit).
    case unknownTypeID(TypeID)
    /// The line did not match the format's grammar.
    case malformedLine(String)
    /// The fit header could not be parsed; without it there is no hull or name.
    case malformedHeader(String)
    /// No fit was found in the data.
    case noFitsFound
    /// The type resolved, but the model has no place for it: cargo is not stored in `FitDocument`.
    case droppedCargo(TypeID, quantity: Int)
    /// The module is marked as not fitted (`_` in DNA); it is cargo, not part of the fit.
    case droppedUnfitted(TypeID)
    /// The charge fit no module of the fit.
    case unboundCharge(TypeID)
    /// The mutaplasmid did not resolve; the item was imported as a regular one.
    case unknownMutaplasmid(String)
    /// The mutation was applied but the rolls were lost: the resolver does not know attribute names
    /// (see `TypeResolver.attributeID(named:)`).
    case mutationRollsDropped(TypeID)
    /// An attribute name in the rolls block is unknown.
    case unknownAttribute(String)
}

/// Result of parsing: any number of fits plus the list of losses (XML and clipboard EFT may hold several fits).
public struct ImportResult: Sendable {
    public var documents: [FitDocument]
    public var warnings: [ImportWarning]

    public init(documents: [FitDocument] = [], warnings: [ImportWarning] = []) {
        self.documents = documents
        self.warnings = warnings
    }

    public var isEmpty: Bool { documents.isEmpty }
}
