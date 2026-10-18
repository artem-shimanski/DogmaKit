//
//  DebugNames.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 02.08.2026.
//

import Synchronization

/// Hook that puts names into `description`/`debugDescription` of identifiers.
///
/// `TypeID` lives here while the name catalog lives in `DogmaText`, which depends on `DogmaModels`, so `DogmaModels`
/// only holds a slot that any outside code can fill:
///
/// ```swift
/// #if DEBUG
/// try? TextCatalog.installAsDebugNames()
/// #endif
/// ```
///
/// Nothing is gated by `#if DEBUG` inside the package. If no catalog is installed the output is the bare number.
public enum DogmaDebug {
    private static let storage = Mutex<(any NameCatalog)?>(nil)

    /// Installs the name catalog; `nil` removes it.
    public static func install(_ catalog: (any NameCatalog)?) {
        storage.withLock { $0 = catalog }
    }

    /// The current catalog. The slot is read under a lock; the name lookup itself happens outside it.
    public static var names: (any NameCatalog)? {
        storage.withLock { $0 }
    }
}

/// Shared output for all SDE identifiers: `Rifter [587]` when a catalog is installed and knows the name, otherwise `587`.
/// `description` and `debugDescription` intentionally match. Note that this changes plain string interpolation too;
/// use `rawValue` where the number itself is needed.
public protocol DogmaIdentifier: RawRepresentable, CustomStringConvertible, CustomDebugStringConvertible
where RawValue: FixedWidthInteger {
    /// Name from the installed catalog; `nil` if there is none or it does not know the ID.
    var debugName: String? { get }
}

extension DogmaIdentifier {
    public var description: String {
        guard let debugName else { return "\(rawValue)" }
        return "\(debugName) [\(rawValue)]"
    }

    public var debugDescription: String { description }
}

extension TypeID: DogmaIdentifier {
    public var debugName: String? { DogmaDebug.names?.name(of: self) }
}

extension GroupID: DogmaIdentifier {
    public var debugName: String? { DogmaDebug.names?.name(of: self) }
}

extension CategoryID: DogmaIdentifier {
    public var debugName: String? { DogmaDebug.names?.name(of: self) }
}

extension MetaGroupID: DogmaIdentifier {
    public var debugName: String? { DogmaDebug.names?.name(of: self) }
}

extension AttributeID: DogmaIdentifier {
    public var debugName: String? { DogmaDebug.names?.name(of: self) }
}

extension AttributeCategoryID: DogmaIdentifier {
    public var debugName: String? { DogmaDebug.names?.name(of: self) }
}

extension EffectID: DogmaIdentifier {
    public var debugName: String? { DogmaDebug.names?.name(of: self) }
}

extension WarfareBuffID: DogmaIdentifier {
    public var debugName: String? { DogmaDebug.names?.name(of: self) }
}

extension UnitID: DogmaIdentifier {
    public var debugName: String? { DogmaDebug.names?.name(of: self) }
}

/// PI schematic. Printed uniformly with the other identifiers (names come from the catalog when installed).
extension SchematicID: DogmaIdentifier {
    public var debugName: String? { DogmaDebug.names?.name(of: self) }
}
