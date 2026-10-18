//
//  TextCatalog+TypeResolver.swift
//  DogmaText
//
//  Created by Artem Shimanski on 02.08.2026.
//

import Foundation
import DogmaModels

/// Name to ID lookup, used by the EFT/XML importers (`DogmaKitIO.FitImporter`).
///
/// The index is built lazily on first resolve and kept in memory, not in the file: normalized keys would nearly
/// double `text-en.bin` and defeat deduplication, and the normalization policy should not be fixed at build time.
extension TextCatalog: TypeResolver {

    public func typeID(named name: String) -> TypeID? {
        index.tables(buildIndex).types[Self.normalized(name)]
    }

    public func attributeID(named name: String) -> AttributeID? {
        index.tables(buildIndex).attributes[Self.normalized(name)]
    }

    /// Case and surrounding whitespace are ignored, as in `DictionaryTypeResolver`.
    static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func buildIndex() -> ReverseIndex.Tables {
        var tables = ReverseIndex.Tables()
        tables.types.reserveCapacity(8192)

        // The view is not stored in a local: it is a borrow of `decoder`, taken afresh by each traversal.
        do {
            let decoder = decoder
            decoder.decode(DogmaTextData.self).types.forEach { pair in
                let id = pair.key.load()
                let name = Self.normalized(pair.value.load())
                guard !name.isEmpty else { return }
                // On a name collision the lowest ID wins, matching the generated `TypeID` constants.
                if let existing = tables.types[name], existing.rawValue <= id.rawValue { return }
                tables.types[name] = id
            }
        }

        do {
            let decoder = decoder
            decoder.decode(DogmaTextData.self).attributes.forEach { pair in
                let id = pair.key.load()
                let name = Self.normalized(pair.value.load())
                guard !name.isEmpty else { return }
                if let existing = tables.attributes[name], existing.rawValue <= id.rawValue { return }
                tables.attributes[name] = id
            }
        }

        return tables
    }
}
