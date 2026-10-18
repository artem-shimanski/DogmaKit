//
//  HitPoints.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 06.07.2026.
//

import simd

@frozen
public struct HitPoints: SIMD, Sendable {
    public typealias Storage = SIMD3<Double>
    public typealias MaskStorage = Storage.MaskStorage
    public typealias ArrayLiteralElement = Storage.ArrayLiteralElement
    public typealias Scalar = Storage.Scalar

    public var storage: Storage

    @inlinable
    public var scalarCount: Int {
        storage.scalarCount
    }
    
    @inlinable
    public init(shield: Scalar, armor: Scalar, hull: Scalar) {
        storage = Storage(shield, armor, hull)
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
    public subscript(index: Int) -> Storage.Scalar {
        get { storage[index] }
        set { storage[index] = newValue }
    }
}

extension HitPoints {
    @inlinable
    public var shield: Scalar {
        get { storage.x }
        set { storage.x = newValue }
    }
    
    @inlinable
    public var armor: Scalar {
        get { storage.y }
        set { storage.y = newValue }
    }
    
    @inlinable
    public var hull: Scalar {
        get { storage.z }
        set { storage.z = newValue }
    }
}

extension HitPoints {
    @inlinable
    public func effective(resonance: Resonance, damagePattern: DamageVector = DamageVector(repeating: 0.25)) -> Self {
        let damageCoefs = damagePattern.storage * resonance.storage
        let safeEpsilon = Storage(repeating: 1e-6)
        let isZeroOrLess = damageCoefs .<= .zero
        
        let safeCoefs = damageCoefs.replacing(with: safeEpsilon, where: isZeroOrLess)
        
        let ehp = storage * (damagePattern.sum() / safeCoefs)
        return Self(storage: ehp)
    }
}
