//
//  EntityID.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 12.06.2026.
//

import BitField

@BitField<UInt16>
public struct EntityID: Hashable, Sendable, CustomDebugStringConvertible {
    
    @usableFromInline
    struct Category: RawRepresentable, Equatable, Sendable {
        @usableFromInline
        var rawValue: UInt8
        
        @inlinable
        init(rawValue: UInt8) {
            self.rawValue = rawValue
        }
        @usableFromInline static let pilot = Category(rawValue: 0)
        @usableFromInline static let skill = Category(rawValue: 1)
        @usableFromInline static let implant = Category(rawValue: 2)
        @usableFromInline static let booster = Category(rawValue: 3)
        @usableFromInline static let hull = Category(rawValue: 4)
        @usableFromInline static let module = Category(rawValue: 5)
        @usableFromInline static let drone = Category(rawValue: 6)
        @usableFromInline static let cargo = Category(rawValue: 7)
        @usableFromInline static let environment = Category(rawValue: 7)
    }
    
    @inlinable @Bit(0..<1) var chargeID: UInt8
    @inlinable @Bit(1..<7) var moduleID: UInt8
    @inlinable @Bit(7..<10) var slot: Entity.Module.Slot!
    
    @inlinable @Bit(1..<7) var droneID: UInt8
    @inlinable @Bit(7..<10) var squadron: Entity.Drone.Squadron!

    @inlinable @Bit(0..<10) var rawID: UInt16
    @inlinable @Bit(10..<13) var category: Category
    @inlinable @Bit(12..<13) var hullID: UInt8
    @inlinable @Bit(3) var pilotID: UInt8
    
    @inlinable @Bit(7..<16, readOnly: true) var allocatorBits: UInt16
    @inlinable @Bit(12..<16, readOnly: true) var domainBits: UInt16
    
    @inlinable var allocatorID: UInt16 {
        if category == .drone || category == .module {
            return allocatorBits
        }
        else {
            return allocatorBits & (UInt16.max ^ 0x7) // clear slot/squadron bits
        }
    }
    
    public static let gang = EntityID(rawValue: 0)
    public static let invalid = EntityID(rawValue: .max)
    
    @inlinable
    public var pilot: EntityID {
        self & Self.$pilotID.higherBitsInclusive
    }
    
    @inlinable
    public var hull: EntityID {
        self & Self.$hullID.higherBitsInclusive
    }
    
    @inlinable
    public var module: EntityID {
        self & Self.$moduleID.higherBitsInclusive
    }

    @inlinable
    public var drone: EntityID {
        self & Self.$droneID.higherBitsInclusive
    }

    /// The charge of a module or drone: shares its owner's `allocatorID` but is not in the allocator's lists.
    @inlinable
    var isCharge: Bool {
        (category == .module || category == .drone) && chargeID == 1
    }

    @inlinable
    public var parent: EntityID {
        switch category {
        case .module:
            return chargeID > 0 ? module : hull
        case .drone:
            return chargeID > 0 ? drone : hull
        case .cargo:
            return hull
        case .skill, .implant, .booster, .hull:
            return pilot
        default:
            return pilotID > 0 ? Self.gang : .invalid
        }
    }
    
    @inlinable
    public func isParent(of child: EntityID) -> Bool {
        let shift = rawValue.trailingZeroBitCount
        return (rawValue >> shift) == (child.rawValue >> shift)
    }
    
    @inlinable
    public static func pilot(_ index: UInt8 = 0) -> Self {
        var id = EntityID(rawValue: 0)
        id.pilotID = index
        return id
    }
    
    @inlinable
    public static func hull(for pilot: EntityID) -> Self {
        var id = pilot.pilot
        id.category = .hull
        return id
    }

    @inlinable
    public static func module(_ index: UInt8 = 0, in slot: Entity.Module.Slot, on hull: EntityID) -> Self {
        var id = hull.hull
        id.category = .module
        id.slot = slot
        id.moduleID = index
        return id
    }

    @inlinable
    public static func charge(in entity: EntityID) -> Self {
        var id = entity
        id.chargeID = 1
        return id
    }

    @inlinable
    public static func drone(_ index: UInt8 = 0, in squadron: Entity.Drone.Squadron = .none, on hull: EntityID) -> Self {
        var id = hull.hull
        id.category = .drone
        id.squadron = squadron
        id.droneID = index
        return id
    }
    
    @inlinable
    public static func cargo(_ index: UInt16 = 0, on hull: EntityID) -> Self {
        var id = hull.hull
        id.category = .cargo
        id.rawID = index
        return id
    }
    
    @inlinable
    public static func skill(_ index: UInt16 = 0, for pilot: EntityID) -> Self {
        var id = pilot.pilot
        id.category = .skill
        id.rawID = index
        return id
    }
    
    @inlinable
    public static func implant(_ index: UInt16 = 0, for pilot: EntityID) -> Self {
        var id = pilot.pilot
        id.category = .implant
        id.rawID = index
        return id
    }
    
    @inlinable
    public static func booster(_ index: UInt16 = 0, for pilot: EntityID) -> Self {
        var id = pilot.pilot
        id.category = .booster
        id.rawID = index
        return id
    }

    /// An environment entity: beacon effect (wormhole, incursion), abyssal weather,
    /// Triglavian storm. The `.environment` category is only used with `pilotID == 0`,
    /// so it never overlaps other allocators. `EntityID.gang` (rawValue 0) stays the domain root.
    @inlinable
    public static func environment(_ index: UInt16 = 0) -> Self {
        var id = EntityID(rawValue: 0)
        id.category = .environment
        id.rawID = index
        return id
    }

    /// Compact path of the entity in the hierarchy:
    ///
    /// ```
    /// gang
    /// invalid
    /// environment[2]
    /// pilot[1]
    /// pilot[1].skill[42]
    /// pilot[1].implant[3]
    /// pilot[1].hull
    /// pilot[1].hull.module[hi:3]
    /// pilot[1].hull.module[hi:3].charge
    /// pilot[1].hull.drone[light:2]
    /// pilot[1].hull.cargo[7]
    /// ```
    ///
    /// Invalid bit combinations print as `?`, an unrecognized `rawValue` as hex.
    public var debugDescription: String {
        if self == .invalid { return "invalid" }
        if self == .gang { return "gang" }

        // pilotID == 0 is outside any pilot; only environment entities live there.
        guard pilotID > 0 else {
            guard category == .environment else { return rawDescription }
            return "environment[\(rawID)]"
        }

        var path = "pilot[\(pilotID)]"

        switch category {
        case .pilot:
            break
        case .skill:
            path += ".skill[\(rawID)]"
        case .implant:
            path += ".implant[\(rawID)]"
        case .booster:
            path += ".booster[\(rawID)]"
        case .hull:
            path += ".hull"
        case .module:
            let slot: Entity.Module.Slot? = self.slot
            path += ".hull.module[\(slot.map { "\($0)" } ?? "?"):\(moduleID)]"
            if chargeID > 0 { path += ".charge" }
        case .drone:
            let squadron: Entity.Drone.Squadron? = self.squadron
            if let squadron {
                path += squadron == .none
                    ? ".hull.drone[\(droneID)]"
                    : ".hull.drone[\(squadron):\(droneID)]"
            }
            else {
                path += ".hull.drone[?:\(droneID)]"
            }
            if chargeID > 0 { path += ".charge" }
        case .cargo:
            path += ".hull.cargo[\(rawID)]"
        default:
            return rawDescription
        }
        return path
    }

    @usableFromInline
    var rawDescription: String {
        "EntityID(0x\(String(rawValue, radix: 16, uppercase: true)))"
    }
}

extension PilotID: CustomDebugStringConvertible {}
extension SkillID: CustomDebugStringConvertible {}
extension ImplantID: CustomDebugStringConvertible {}
extension BoosterID: CustomDebugStringConvertible {}
extension HullID: CustomDebugStringConvertible {}
extension ModuleID: CustomDebugStringConvertible {}
extension DroneID: CustomDebugStringConvertible {}
extension EnvironmentID: CustomDebugStringConvertible {}
extension ChargeID: CustomDebugStringConvertible {}

extension RawRepresentable where RawValue == EntityID {
    public var debugDescription: String { rawValue.debugDescription }
}

public struct PilotID: RawRepresentable, Sendable, Hashable {
    public let rawValue: EntityID
    
    @inlinable
    public init(rawValue: EntityID) { self.rawValue = rawValue }
    
    @inlinable
    public init(_ index: UInt8) {
        // A wider index would be silently truncated and alias another pilot (9 → 1).
        precondition(index <= EntityID.$pilotID.maxValue, "pilot index out of range")
        self.init(rawValue: EntityID.pilot(index))
    }
    
    @inlinable
    public var hull: HullID {
        HullID(rawValue: EntityID.hull(for: rawValue))
    }
}

public struct SkillID: RawRepresentable, Sendable, Hashable {
    public let rawValue: EntityID
    
    @inlinable
    public init(rawValue: EntityID) { self.rawValue = rawValue }
}

public struct ImplantID: RawRepresentable, Sendable, Hashable {
    public let rawValue: EntityID
    
    @inlinable
    public init(rawValue: EntityID) { self.rawValue = rawValue }
}

public struct BoosterID: RawRepresentable, Sendable, Hashable {
    public let rawValue: EntityID
    
    @inlinable
    public init(rawValue: EntityID) { self.rawValue = rawValue }
}

public struct HullID: RawRepresentable, Sendable, Hashable {
    public let rawValue: EntityID
    
    @inlinable
    public init(rawValue: EntityID) { self.rawValue = rawValue }
    
    @inlinable
    public var pilot: PilotID {
        PilotID(rawValue: rawValue.pilot)
    }

}

public struct ModuleID: RawRepresentable, Sendable, Hashable {
    public let rawValue: EntityID
    
    @inlinable
    public init(rawValue: EntityID) { self.rawValue = rawValue }
    
    @inlinable
    public var charge: ChargeID {
        ChargeID(rawValue: EntityID.charge(in: rawValue))
    }
    
    @inlinable
    public var hull: HullID {
        HullID(rawValue: rawValue.hull)
    }
}

public struct DroneID: RawRepresentable, Sendable, Hashable {
    public let rawValue: EntityID
    
    @inlinable
    public init(rawValue: EntityID) { self.rawValue = rawValue }
    
    @inlinable
    public var charge: ChargeID {
        ChargeID(rawValue: EntityID.charge(in: rawValue))
    }
    
    @inlinable
    public var hull: HullID {
        HullID(rawValue: rawValue.hull)
    }
}

/// An environment effect (beacon, weather, storm). See `EntityID.environment`.
public struct EnvironmentID: RawRepresentable, Sendable, Hashable {
    public let rawValue: EntityID

    @inlinable
    public init(rawValue: EntityID) { self.rawValue = rawValue }

    @inlinable
    public init(_ index: UInt16) {
        self.init(rawValue: EntityID.environment(index))
    }
}

public struct ChargeID: RawRepresentable, Sendable, Hashable {
    public let rawValue: EntityID
    
    @inlinable
    public init(rawValue: EntityID) { self.rawValue = rawValue }
}
