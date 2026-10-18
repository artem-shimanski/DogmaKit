//
//  NameCatalog.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 02.08.2026.
//

/// Identifier to name; the reverse of `TypeResolver`. Declared here because names are consumer data.
/// The ready-made implementation is `DogmaText.TextCatalog`. Every requirement defaults to `nil`, so a catalog may
/// implement any subset.
public protocol NameCatalog: Sendable {
    func name(of id: TypeID) -> String?
    func name(of id: GroupID) -> String?
    func name(of id: CategoryID) -> String?
    func name(of id: MetaGroupID) -> String?
    func name(of id: AttributeID) -> String?
    func name(of id: AttributeCategoryID) -> String?
    func name(of id: EffectID) -> String?
    func name(of id: WarfareBuffID) -> String?
    func name(of id: UnitID) -> String?
    func name(of id: SchematicID) -> String?
}

extension NameCatalog {
    public func name(of id: TypeID) -> String? { nil }
    public func name(of id: GroupID) -> String? { nil }
    public func name(of id: CategoryID) -> String? { nil }
    public func name(of id: MetaGroupID) -> String? { nil }
    public func name(of id: AttributeID) -> String? { nil }
    public func name(of id: AttributeCategoryID) -> String? { nil }
    public func name(of id: EffectID) -> String? { nil }
    public func name(of id: WarfareBuffID) -> String? { nil }
    public func name(of id: UnitID) -> String? { nil }
    public func name(of id: SchematicID) -> String? { nil }
}
