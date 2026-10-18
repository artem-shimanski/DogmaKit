//
//  TextCatalog+NameCatalog.swift
//  DogmaText
//
//  Created by Artem Shimanski on 02.08.2026.
//

import DogmaModels

/// The conformance body is empty: `TextCatalog.name(of:)` overloads already satisfy the protocol.
extension TextCatalog: NameCatalog {}

extension TextCatalog {

    /// Makes `description`/`debugDescription` of all SDE identifiers show names. Call at app or test start:
    ///
    /// ```swift
    /// #if DEBUG
    /// try? TextCatalog.installAsDebugNames()
    /// #endif
    /// ```
    @discardableResult
    public static func installAsDebugNames() throws -> TextCatalog {
        let catalog = try english()
        DogmaDebug.install(catalog)
        return catalog
    }
}
