//
//  Tank.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 06.07.2026.
//

@frozen
public struct Tank: SIMD, Sendable {
    public typealias Storage = SIMD4<Double>
    public typealias MaskStorage = Storage.MaskStorage
    public typealias ArrayLiteralElement = Storage.ArrayLiteralElement
    public typealias Scalar = Storage.Scalar

    public var storage: Storage

    @inlinable
    public var scalarCount: Int {
        storage.scalarCount
    }

    @inlinable
    public init() {
        storage = Storage()
    }

    @inlinable
    public init(storage: Storage) {
        self.storage = storage
    }
    
    @inlinable
    public init(passiveShield: Scalar, shieldRepair: Scalar, armorRepair: Scalar, hullRepair: Scalar) {
        storage = Storage(passiveShield, shieldRepair, armorRepair, hullRepair)
    }

    
    @inlinable
    public subscript(index: Int) -> Storage.Scalar {
        get { storage[index] }
        set { storage[index] = newValue }
    }
}
extension Tank {
    
    @inlinable
    public var passiveShield: Scalar {
        get { storage.x }
        set { storage.x = newValue}
    }
    
    @inlinable
    public var shieldRepair: Scalar {
        get { storage.y }
        set { storage.y = newValue}
    }
    
    @inlinable
    public var armorRepair: Scalar {
        get { storage.z }
        set { storage.z = newValue}
    }
    
    @inlinable
    public var hullRepair: Scalar  {
        get { storage.w }
        set { storage.w = newValue}
    }
}

extension Tank {
    /// Active repair component for the given layer.
    @inlinable
    public subscript(repair kind: FitStats.Module.RepairKind) -> Scalar {
        get {
            switch kind {
            case .shield: shieldRepair
            case .armor: armorRepair
            case .hull: hullRepair
            }
        }
        set {
            switch kind {
            case .shield: shieldRepair = newValue
            case .armor: armorRepair = newValue
            case .hull: hullRepair = newValue
            }
        }
    }
}

extension Tank {
    @inlinable
    public func effective(resonance: Resonance, damagePattern: DamageVector = DamageVector(repeating: 0.25)) -> Self {
        // Passive shield regen and shield repair both go through the shield resonance.
        let layers = resonance.storage.applied(to: damagePattern.storage)
        let damageCoefs = Storage(layers.x, layers.x, layers.y, layers.z)
        let safeEpsilon = Storage(repeating: 1e-6)
        let isZeroOrLess = damageCoefs .<= .zero
        
        let safeCoefs = damageCoefs.replacing(with: safeEpsilon, where: isZeroOrLess)
        
        let ehp = storage * (damagePattern.sum() / safeCoefs)
        return Self(storage: ehp)
    }
}
