//
//  TypeResolver.swift
//  DogmaKitIO
//
//  Created by Artem Shimanski on 02.08.2026.
//

import Foundation
import DogmaKit

// The `TypeResolver` protocol itself is declared in `DogmaModels` so that `DogmaText.TextCatalog` can implement it
// without `DogmaKitIO` depending on `DogmaText`.

/// A resolver over ready-made dictionaries. Names are normalized (case and surrounding whitespace ignored).
/// Alternatively use the `DogmaText` target, whose `TextCatalog` implements `TypeResolver` itself.
public struct DictionaryTypeResolver: TypeResolver {
    private let types: [String: TypeID]
    private let attributes: [String: AttributeID]

    public init(types: [String: TypeID], attributes: [String: AttributeID] = [:]) {
        self.types = Dictionary(types.map { (Self.normalized($0.key), $0.value) },
                                uniquingKeysWith: { first, _ in first })
        self.attributes = Dictionary(attributes.map { (Self.normalized($0.key), $0.value) },
                                     uniquingKeysWith: { first, _ in first })
    }

    public func typeID(named name: String) -> TypeID? {
        types[Self.normalized(name)]
    }

    public func attributeID(named name: String) -> AttributeID? {
        attributes[Self.normalized(name)]
    }

    private static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
