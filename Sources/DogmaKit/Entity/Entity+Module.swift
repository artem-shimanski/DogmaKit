//
//  Entity+Module.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 16.06.2026.
//

import DogmaModels
import BitField

extension Entity {
    
    public struct Module: BitwiseCopyable, Sendable {

        /// Whether the module type can target another hull: it has an effect of category
        /// `.target` whose modifiers apply to the `.target` domain (remote repair, warp disruptor,
        /// ECM, neuts). The category alone is not enough: weapons are `.target` too, but their
        /// damage bypasses modifiers.
        static func isProjectable(_ type: DogmaSDE.TypeInfo.View) -> Bool {
            var result = false
            type.effects.forEach { effect in
                guard !result, effect.category.load() == .target else { return }
                effect.modifiers.forEach {
                    if $0.load().domain == .target { result = true }
                }
            }
            return result
        }

        public var state: State = .offline
        public let hardpoint: Hardpoint
        public let slot: Slot

        /// Physical slot index in the rack, not the list order. Assigned in `Fit.Modules.add`
        /// as the first free index and changed via `Fit.Module.socket`; removing a module
        /// leaves a gap. Matters for heat: damage to neighbours falls off as
        /// `heatAttenuation ^ |Δsocket|`.
        public var socket: UInt8 = 0

        public let flags: Flags
        public var target: EntityID = .invalid
        public let defaultReloadTime: Double

        /// `base` is the base type of a mutated (abyssal) module, see `Mutation`. Slot,
        /// hardpoint, flags and `defaultReloadTime` come from the resulting type's effects;
        /// attributes fall back to the base type. Throws `DogmaError.noSlot` for a type with
        /// no slot effect: such a type cannot be fitted anywhere.
        init(_ type: DogmaSDE.TypeInfo.View, base: DogmaSDE.TypeInfo.View? = nil) throws(DogmaError) {
            var slot: Slot? = nil
            var hardpoint = Hardpoint.none
            var flags = Flags(rawValue: 0)
            var defaultReloadTime: Double = -1
            
            type.effects.forEach { effect in
                switch effect.id.load() {
                case .loPower: slot = .low
                case .medPower: slot = .med
                case .hiPower: slot = .hi
                case .rigSlot: slot = .rig
                case .subSystem: slot = .subsystem
                case .tacticalMode: slot = .mode
                case .serviceSlot: slot = .service
                case .turretFitted: hardpoint = .turret
                case .launcherFitted: hardpoint = .launcher
                case .online, .onlineForStructures: flags.canBeOnline = true
                case .miningLaser, .targetAttack, .useMissiles: defaultReloadTime = 1
                case .powerBooster, .projectileFired: defaultReloadTime = 10
                default: break
                }
                
                switch effect.category.load() {
                case .overload: flags.canBeOverloaded = true
                case .target: flags.requireTarget = true
                case .activation: flags.canBeActive = true
                default: break
                }
            }
            flags.canBeActive = flags.canBeActive || flags.canBeOverloaded || flags.requireTarget
            
            // Abyssal modules keep charge requirements on the base type.
            var forceReload = type.groupID.load() == .capacitorBooster
            if !forceReload, let requirements = type.chargeRequirements {
                forceReload = requirements.chargeGroup.contains {
                    let groupID = $0.load()
                    return groupID == .capacitorBoosterCharge || groupID == .naniteRepairPaste
                }
            }
            else if !forceReload, let base, let requirements = base.chargeRequirements {
                forceReload = requirements.chargeGroup.contains {
                    let groupID = $0.load()
                    return groupID == .capacitorBoosterCharge || groupID == .naniteRepairPaste
                }
            }
            flags.forceReload = forceReload

            guard let slot else { throw DogmaError.noSlot(type.id.load()) }

            self.hardpoint = hardpoint
            self.slot = slot
            self.flags = flags
            self.defaultReloadTime = defaultReloadTime
            // Default to the type's highest state, but not overload. Rigs and subsystems have no online effect, so `.offline`.
            self.state = min(flags.maxAllowedState, .active)
        }
    }
}

extension Entity.Module {

    /// Upper bound of socket indices; matches the module allocator capacity (63 per rack),
    /// so a free socket always exists in this range.
    static let socketCount: UInt8 = 64

    public enum State: UInt8, BitwiseCopyable, Sendable, Comparable {
        public static func < (lhs: State, rhs: State) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
        
        case offline
        case online
        case active
        case overloaded
    }
    
    public enum Slot: UInt8, BitwiseCopyable, Sendable, CaseIterable {
        case hi
        case med
        case low
        case rig
        case subsystem
        case mode
        case service
        
        var attributeID: AttributeID {
            switch self {
            case .hi: .hiSlots
            case .med: .medSlots
            case .low: .lowSlots
            case .rig: .rigSlots
            case .subsystem: .maxSubSystems
            case .mode: .tacticalModes
            case .service: .serviceSlots
            }
        }

        /// The hull's heat attributes for this rack; only hi/med/low racks heat.
        ///
        /// Mind the IDs: `heatAttenuationMed` is 1261 (1260 is a duplicate,
        /// `heatAttenuationMedium`), `heatDissipationRateMed` is 1196, not 1197.
        var heatAttributeIDs: (capacity: AttributeID, attenuation: AttributeID, dissipation: AttributeID)? {
            switch self {
            case .hi: (.heatCapacityHi, .heatAttenuationHi, .heatDissipationRateHi)
            case .med: (.heatCapacityMed, .heatAttenuationMed, .heatDissipationRateMed)
            case .low: (.heatCapacityLow, .heatAttenuationLow, .heatDissipationRateLow)
            default: nil
            }
        }
    }
    
    public enum Hardpoint: BitwiseCopyable, Sendable {
        case none
        case launcher
        case turret
    }

    /// Strategic cruiser subsystem slot (the `subSystemSlot` attribute value; raw values
    /// match the SDE). Each slot holds exactly one subsystem; a T3C needs all four to have
    /// slots, CPU and powergrid.
    public enum SubsystemSlot: UInt8, BitwiseCopyable, Sendable, CaseIterable {
        case core = 125
        case defensive = 126
        case offensive = 127
        case propulsion = 128
    }
    
    @BitField<UInt8>
    public struct Flags: Sendable {
        @Bit(1) public var canBeOnline: Bool
        @Bit(1) public var canBeActive: Bool
        @Bit(1) public var canBeOverloaded: Bool
        @Bit(1) public var forceReload: Bool
        @Bit(1) public var requireTarget: Bool
        
        /// The highest state the module supports.
        public var maxAllowedState: State {
            if canBeOverloaded {
                return .overloaded
            }
            else if canBeActive {
                return .active
            }
            else if canBeOnline {
                return .online
            }
            else {
                return .offline
            }
        }
    }
}


extension Entity.Module.State {
    var effectCategories: DogmaSDE.Effect.Category {
        switch self {
        case .offline:
            return [.passive]
        case .online:
            return [.passive, .online]
        case .active:
            return [.passive, .online, .activation, .target]
        case .overloaded:
            return [.passive, .online, .activation, .target, .overload]
        }
    }
}

extension DogmaSDE.Effect.Category {
    var minState: Entity.Module.State {
        switch self {
        case .online:
            return .online
        case .activation, .target:
            return .active
        case .overload:
            return .overloaded
        default:
            return .offline
        }
    }
}
