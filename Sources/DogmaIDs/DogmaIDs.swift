//
//  DogmaIDs.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 25.08.2026.
//

public protocol SDEIdentifier: RawRepresentable, BitwiseCopyable, ExpressibleByIntegerLiteral, Codable, Sendable, Hashable, Comparable
where RawValue: FixedWidthInteger, IntegerLiteralType == RawValue {
}

extension SDEIdentifier {
    @inlinable
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct AttributeID: SDEIdentifier {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }
    public init(integerLiteral value: UInt16) { rawValue = value }
}

public struct AttributeCategoryID: SDEIdentifier {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }
    public init(integerLiteral value: UInt16) { rawValue = value }
}

public struct EffectID: SDEIdentifier {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }
    public init(integerLiteral value: UInt16) { rawValue = value }
}

public struct WarfareBuffID: SDEIdentifier {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }
    public init(integerLiteral value: UInt16) { rawValue = value }
}

public struct TypeID: SDEIdentifier {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public init(integerLiteral value: UInt32) { rawValue = value }
}

public struct GroupID: SDEIdentifier {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }
    public init(integerLiteral value: UInt16) { rawValue = value }
}

public struct MetaGroupID: SDEIdentifier {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }
    public init(integerLiteral value: UInt16) { rawValue = value }
}

public struct CategoryID: SDEIdentifier {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }
    public init(integerLiteral value: UInt16) { rawValue = value }
}

public struct SchematicID: SDEIdentifier {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }
    public init(integerLiteral value: UInt16) { rawValue = value }
}

public struct UnitID: SDEIdentifier {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }
    public init(integerLiteral value: UInt16) { rawValue = value }
}
