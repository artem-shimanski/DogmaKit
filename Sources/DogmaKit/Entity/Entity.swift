//
//  Item.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 16.06.2026.
//

import DogmaModels
import FlatBin

public struct Entity: BitwiseCopyable, Identifiable, Sendable {
    public enum Kind: BitwiseCopyable, Sendable {
        case invlaid
        case environment
        case pilot
        case skill(level: UInt8)
        case implant(slot: UInt16)
        case booster(slot: UInt16)
        case ship
        case module(Module)
        case drone(Drone)
        case charge(Charge)
        case cargo
        case station
        
        @inlinable
        public var module: Module? {
            get {
                if case let .module(state) = self { return state }
                return nil
            }
            set {
                if let newValue { self = .module(newValue) }
            }
        }

        @inlinable
        public var drone: Drone? {
            get {
                if case let .drone(state) = self { return state }
                return nil
            }
            set {
                if let newValue { self = .drone(newValue) }
            }
        }
        
        @inlinable
        public var charge: Charge? {
            get {
                if case let .charge(state) = self { return state }
                return nil
            }
            set {
                if let newValue { self = .charge(newValue) }
            }
        }

        @inlinable
        public var skillLevel: UInt8? {
            get {
                if case let .skill(level) = self { return level }
                return nil
            }
            set {
                if let newValue { self = .skill(level: newValue) }
            }
        }
        
        @inlinable
        public var implantSlot: UInt16? {
            if case let .implant(slot: slot) = self { return slot }
            return nil
        }

        @inlinable
        public var boosterSlot: UInt16? {
            if case let .booster(slot: slot) = self { return slot }
            return nil
        }

    }
    public var id: EntityID
    public var typeID: TypeID
    public var groupID: GroupID
    public var categoryID: CategoryID
    public var info: FlatReference<DogmaSDE.TypeInfo>
    /// Mutation (abyssal item): references to the mutaplasmid and base type; `nil` for
    /// regular entities. Rolls are stored in `EntityStore.mutations`, see `Mutation`.
    public var mutation: Mutation? = nil
    public var kind: Kind
}
