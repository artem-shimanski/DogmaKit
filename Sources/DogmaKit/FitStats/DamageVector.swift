//
//  DamageVector.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 05.07.2026.
//

@frozen
public struct DamageVector: SIMD, Sendable {
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
    public init(em: Scalar, thermal: Scalar, kinetic: Scalar, explosive: Scalar) {
        storage = Storage(em, thermal, kinetic, explosive)
    }
    
    @inlinable
    public subscript(index: Int) -> Storage.Scalar {
        get { storage[index] }
        set { storage[index] = newValue }
    }
}

extension DamageVector {
    
    @inlinable
    public var em: Scalar {
        get { storage.x }
        set { storage.x = newValue}
    }
    
    @inlinable
    public var thermal: Scalar {
        get { storage.y }
        set { storage.y = newValue}
    }
    
    @inlinable
    public var kinetic: Scalar {
        get { storage.z }
        set { storage.z = newValue}
    }
    
    @inlinable
    public var explosive: Scalar  {
        get { storage.w }
        set { storage.w = newValue}
    }
}



extension DamageVector {
    @inlinable
    public func effective(resistances: DamageVector) -> DamageVector {
        self * (1 - resistances)
    }
}
