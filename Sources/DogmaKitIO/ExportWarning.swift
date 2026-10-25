//
//  ExportWarning.swift
//  DogmaKitIO
//

import DogmaKit

/// Something a public format could not hold. Export does not fail; it reports what it dropped.
public enum ExportWarning: Error, Sendable, Equatable {
    /// The name catalog has no name for the type; the item was omitted.
    case unnamedType(TypeID)
    /// The name catalog has no internal name for the attribute; the mutation roll was omitted.
    case unnamedAttribute(AttributeID)
    /// The pilot has no ship, so there is no fit to write; the index is the pilot's position in the document.
    case noShip(pilot: Int)
    /// The format has no place for the item (implants and boosters in DNA and XML).
    case unsupportedItem(TypeID)
    /// The format cannot describe mutations (DNA and XML); the item was written as its base type.
    case droppedMutation(TypeID)
}

/// Result of exporting: the text plus the list of losses.
public struct ExportResult: Sendable {
    public var text: String
    public var warnings: [ExportWarning]

    public init(text: String = "", warnings: [ExportWarning] = []) {
        self.text = text
        self.warnings = warnings
    }
}
