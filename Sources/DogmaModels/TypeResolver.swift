//
//  TypeResolver.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 02.08.2026.
//

/// Name to identifier mapping.
///
/// EFT and XML formats reference types ONLY by name, and names are localized, so they are not part of `sde.bin`.
/// Declared in `DogmaModels` because both `DogmaKitIO` and `DogmaText` (whose `TextCatalog` implements it) can see it.
/// Everything else (category, group, charge compatibility) importers take from `DogmaKit.TypeCatalog`.
public protocol TypeResolver: Sendable {

    /// `nil` if the name is unknown. The implementation decides how lenient the comparison is (case, whitespace, locale).
    func typeID(named name: String) -> TypeID?

    /// Internal (NOT localized) attribute name, e.g. `speedFactor`, `cpu`. Used only for the mutation rolls in the
    /// EFT dialect with mutations, which write the SDE attribute name.
    ///
    /// The default returns `nil`: the mutation is still applied, but the rolls are dropped (with a warning).
    func attributeID(named name: String) -> AttributeID?
}

extension TypeResolver {
    public func attributeID(named name: String) -> AttributeID? { nil }
}
