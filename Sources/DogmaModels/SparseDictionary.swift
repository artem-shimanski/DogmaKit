//
//  SparseDictionary.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 21.06.2026.
//

import FlatBin

@FlatCodable
public struct SparseDictionary<Key: RawRepresentable & Hashable, Value: FlatCodable>: ExpressibleByDictionaryLiteral where Key.RawValue: BinaryInteger & FlatRawCodable {
    public var values: [Value] = []
    public var valueIndices: [Int32] = []
    
    public init(_ elements: some Collection<(key: Key, value: Value)>) {
        guard !elements.isEmpty else {return}
        
        self.values.reserveCapacity(elements.count)
        let maxID = elements.max{$0.key.rawValue < $1.key.rawValue}!.key.rawValue
        valueIndices = .init(repeating: -1, count: Int(maxID + 1))
        for (key, value) in elements {
            valueIndices[Int(key.rawValue)] = Int32(self.values.count)
            self.values.append(value)
        }
    }
    public init() {}
    
    @inlinable
    public subscript(_ key: Key) -> Value? {
        let k = Int(key.rawValue)
        guard k >= 0 && k < valueIndices.count && valueIndices[k] >= 0 else {return nil}
        return values[Int(valueIndices[k])]
    }
    
    public init(dictionaryLiteral elements: (Key, Value)...) {
        self.init(elements)
    }
}

extension SparseDictionary.View {
    @inlinable
    public subscript(_ key: Key) -> Value.View? {
        @_lifetime(copy self)
        get {
            let k = Int(key.rawValue)
            guard k >= 0 && k < valueIndices.count else {return nil}
            let id = valueIndices[k].load()
            guard id >= 0 else {return nil}
            return values[Int(id)]
        }
    }
}

extension SparseDictionary: Sendable where Key: Sendable, Value: Sendable {}
