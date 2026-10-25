//
//  Entity+Charge.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 08.07.2026.
//

import BitField

extension Entity {

    public struct Charge: BitwiseCopyable, Sendable {
        public var flags: Flags
        
        init(_ type: DogmaSDE.TypeInfo.View) {
            var flags = Flags(rawValue: 0)
            type.effects.forEach { effect in
                switch effect.category.load() {
                case .target:
                    flags.requireTarget = true
                    flags.canBeActive = true
                    let options = effect.options.load()
                    if options.contains(.isAssistance) {
                        flags.isAssistance = true
                    }
                    if options.contains(.isOffensive) {
                        flags.isOffensive = true
                    }
                case .activation, .overload:
                    flags.canBeActive = true
                default:
                    break
                }
            }
            flags.dealsDamage = (type.attributes[.emDamage]?.load() ?? type.attributes[.explosiveDamage]?.load() ?? type.attributes[.kineticDamage]?.load() ?? type.attributes[.thermalDamage]?.load() ?? 0) > 0
            self.flags = flags
        }
    }
}

extension Entity.Charge {
    
    @BitField<UInt8>
    public struct Flags: Sendable {
        @Bit(1) public var canBeActive: Bool
        @Bit(1) public var requireTarget: Bool
        @Bit(1) public var isAssistance: Bool
        @Bit(1) public var isOffensive: Bool
        @Bit(1) public var dealsDamage: Bool
        
        var maxAllowedState: Entity.Module.State {
            return canBeActive ? Entity.Module.State.active : .online
        }
    }

    public enum Size: UInt8, Sendable {
        case none = 0
        case small = 1
        case medium = 2
        case large = 3
        case xLarge = 4
    }
}
