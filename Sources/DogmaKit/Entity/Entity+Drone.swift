//
//  Entity+Drone.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 02.07.2026.
//

import DogmaModels
import BitField

extension Entity {

    public struct Drone: BitwiseCopyable, Sendable {
        public let squadron: Squadron
        public var target: EntityID = .invalid
        public var flags: Flags
        /// Maximum squadron/stack size: `fighterSquadronMaxSize` for fighters, 5 for drones.
        public let squadronSize: UInt8
        /// Number of drones in the stack / fighters in the squadron. One entity represents the
        /// whole stack: additive outputs (damage, mining, neut) are multiplied by `count`.
        public var count: UInt8

        /// `base` is the base type of a mutated drone, see `Mutation`. Flags come from the
        /// resulting type's effects; attributes fall back to the base type (mutated drone
        /// types carry no damage attributes of their own).
        init(_ type: DogmaSDE.TypeInfo.View, base: DogmaSDE.TypeInfo.View? = nil) {
            var flags = Flags(rawValue: 0)
            type.effects.forEach { effect in
                if effect.category.load() == .target {
                    let options = effect.options.load()
                    if options.contains(.isAssistance) {
                        flags.isAssistance = true
                    }
                    if options.contains(.isOffensive) {
                        flags.isOffensive = true
                    }
                }
                if effect.id.load() == .fighterAbilityKamikaze {
                    flags.hasKamikazeAbility = true
                }
            }
            
            for id in Global.droneDamageAttributes {
                if let damage = typeAttribute(id, of: type, base: base), damage > 0 {
                    flags.dealsDamage = true
                    break
                }
            }

            if typeAttribute(.fighterSquadronIsHeavy, of: type, base: base) != nil {self.squadron = .heavy }
            else if typeAttribute(.fighterSquadronIsLight, of: type, base: base) != nil {self.squadron = .light }
            else if typeAttribute(.fighterSquadronIsSupport, of: type, base: base) != nil {self.squadron = .support }
            else if typeAttribute(.fighterSquadronIsStandupHeavy, of: type, base: base) != nil {self.squadron = .standupHeavy }
            else if typeAttribute(.fighterSquadronIsStandupLight, of: type, base: base) != nil {self.squadron = .standupLight }
            else if typeAttribute(.fighterSquadronIsStandupSupport, of: type, base: base) != nil {self.squadron = .standupSupport }
            else {self.squadron = .none}

            // Squadron size; `count` defaults to a full squadron.
            if let maxSize = typeAttribute(.fighterSquadronMaxSize, of: type, base: base), maxSize >= 1 {
                self.squadronSize = UInt8(min(maxSize, 255))
            } else {
                self.squadronSize = 5
            }
            self.count = self.squadronSize

            self.flags = flags
        }

    }
    
}

extension Entity.Drone {
    public enum Squadron: UInt8, Sendable, CaseIterable, BitwiseCopyable {
        case none
        case heavy
        case light
        case support
        case standupHeavy
        case standupLight
        case standupSupport

        /// The hull attribute with this squadron type's slot count; `nil` for `.none`.
        var slotsAttributeID: AttributeID? {
            switch self {
            case .none: nil
            case .heavy: .fighterHeavySlots
            case .light: .fighterLightSlots
            case .support: .fighterSupportSlots
            case .standupHeavy: .fighterStandupHeavySlots
            case .standupLight: .fighterStandupLightSlots
            case .standupSupport: .fighterStandupSupportSlots
            }
        }
    }

    @BitField<UInt8>
    public struct Flags: Sendable, Equatable {
        @Bit(1) public var isActive: Bool
        @Bit(1) public var isKamikaze: Bool
        @Bit(1) public var isAssistance: Bool
        @Bit(1) public var isOffensive: Bool
        @Bit(1) public var dealsDamage: Bool
        @Bit(1) public var hasKamikazeAbility: Bool
    }
}
