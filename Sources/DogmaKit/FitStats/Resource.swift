//
//  Resource.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 06.07.2026.
//

@frozen
public struct Resource: Sendable {
    public var used: Double
    public var total: Double

    @inlinable
    public init(used: Double, total: Double) {
        self.used = used
        self.total = total
    }

    @inlinable
    public var available: Double { total - used }
    
    @inlinable
    public var isOverloaded: Bool { used > total }
}

@frozen
public struct SlotCapacity: Sendable {
    public var used: Int
    public var total: Int

    @inlinable
    public init(used: Int, total: Int) {
        self.used = used
        self.total = total
    }

    @inlinable
    public var available: Int { total - used }
    
    @inlinable
    public var hasFreeSlots: Bool { used < total }

    /// More slots are used than the hull provides (not the same as having no free slots).
    @inlinable
    public var isOverloaded: Bool { used > total }
}
