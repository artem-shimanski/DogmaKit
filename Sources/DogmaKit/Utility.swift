//
//  Utility.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 23.06.2026.
//


import DogmaModels
import simd

extension Array {
    init(minimumCapacity: Int) {
        self.init()
        self.reserveCapacity(minimumCapacity)
    }
}

extension DogmaSDE.Modifier.Domain {
    
    @inlinable
    func resolve(for entity: Entity, from entities: borrowing EntityStore) -> EntityIDSequece {
        switch self {
        case .`self`:
            return .one(entity.id)
        case .gang, .environment:
            // All pilots in the session are treated as one fleet, so the gang domain
            // expands to every hull regardless of the source.
            return .hulls(entities.hulls())
        case .pilot:
            switch entity.kind {
            case .environment:
                return .enumerator(entities.ids(in: .pilot()))
            default:
                return .one(entity.id.pilot)
            }
        case .other:
            // Environment entities have no parent hull; a modifier on a nonexistent
            // entity would crash `AttributeRegistry`.
            if case .environment = entity.kind { return .empty }
            return .one(entity.id.parent)
        case .hull:
            switch entity.kind {
            case .environment:
                return .hulls(entities.hulls())
            default:
                return .one(EntityID.hull(for: entity.id.pilot))
            }
        case .target:
            switch entity.kind {
            case let .module(module):
                if entities[module.target] != nil {
                    return .one(module.target)
                }
            case let .drone(drone):
                if entities[drone.target] != nil {
                    return .one(drone.target)
                }
            case .charge:
                if let module = entities[entity.id.module]?.kind.module,
                   entities[module.target] != nil {
                    return .one(module.target)
                }
            default:
                return .empty
            }
        }
        return .empty
    }
    
}


extension DogmaSDE.TypeInfo.FittingRequirements.View {
    func canFit(to type: DogmaSDE.TypeInfo.View) -> Bool {
        if !canFitShipType.isEmpty && canFitShipType.contains(type.id.load()) {
            return true
        }
        else if !canFitShipGroup.isEmpty && canFitShipGroup.contains(type.groupID.load()) {
            return true
        }
        else {
            return canFitShipType.isEmpty && canFitShipGroup.isEmpty
        }
    }
    
}

extension DogmaSDE.TypeInfo.ChargeRequirements.View {
    func canLoad(with charge: DogmaSDE.TypeInfo.View) -> Bool {
        guard chargeGroup.contains(charge.groupID.load())
        else {return false}
        
        if chargeSize != 0 && chargeSize != (charge.attributes[.chargeSize]?.load()).map(UInt8.init) {
            return false
        }
        
        return true
    }
}

extension simd_double3x4 {
    @inlinable
    init(repeating scalar: Double) {
        let c = SIMD4<Double>(repeating: scalar)
        self.init(c, c, c)
    }
}

extension Sequence {
    func count() -> Int {
        reduce(0) {count, _ in count + 1}
    }
}

enum Global {
    static let cycleTimeAttributes: [AttributeID] = [
        .speed, .duration, .durationSensorDampeningBurstProjector, .durationTargetIlluminationBurstProjector, .durationECMJammerBurstProjector, .durationWeaponDisruptionBurstProjector, .missileLaunchDuration, .durationHighisGood
    ]

    static let droneCycleTimeAttributes: [AttributeID] = [
        .speed, .duration, .fighterAbilityLaunchBombDuration
    ]

    static let optimalAttributes: [AttributeID] = [
        .maxRange,
        .shieldTransferRange,
        .powerTransferRange,
        .energyNeutralizerRangeOptimal,
        .empFieldRange,
        .ecmBurstRange,
        .warpScrambleRange,
        .cargoScanRange,
        .shipScanRange,
        .surveyScanRange
    ]
    
    static let falloffAttributes: [AttributeID] = [
        .falloff, .shipScanFalloff, .falloffEffectiveness
    ]
    
    static let highPriorityAttributes: Set<AttributeID> = [
        .activationBlocked,
        .maxGroupActive,
        .maxGroupOnline,
        .maxGroupFitted,
        .disallowAssistance,
        .disallowOffensiveModifiers
    ]
    
    static let droneDamageAttributes: [AttributeID] = [
        .emDamage,
        .explosiveDamage,
        .kineticDamage,
        .thermalDamage,
        .fighterAbilityMissilesDamageMultiplier,
        .fighterAbilityAttackMissileDamageMultiplier,
        .fighterAbilityAttackTurretDamageMultiplier
    ]
}
