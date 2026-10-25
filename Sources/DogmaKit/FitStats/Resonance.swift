//
//  Resonance.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 06.07.2026.
//

@frozen
public struct Resonance: Sendable, Equatable {
    public typealias Storage = DamageMatrix
    public var storage: Storage
    
    @inlinable
    public init() {
        storage = Storage()
    }

    @inlinable
    public init(storage: Storage) {
        self.storage = storage
    }
    
    @inlinable
    public init(shield: DamageVector, armor: DamageVector, hull: DamageVector) {
        storage = Storage(shield.storage, armor.storage, hull.storage)
    }
}

extension Resonance {
    @inlinable
    public var shield: DamageVector {
        get { DamageVector(storage: storage[0]) }
        set { storage[0] = newValue.storage }
    }
    
    @inlinable
    public var armor: DamageVector {
        get { DamageVector(storage: storage[1]) }
        set { storage[1] = newValue.storage }
    }

    @inlinable
    public var hull: DamageVector {
        get { DamageVector(storage: storage[2]) }
        set { storage[2] = newValue.storage }
    }
    
    @inlinable
    public var resistances: Resistances {
        let one = Storage(repeating: 1)
        return Resistances(storage: one - storage)
    }
}

