//
//  PerfectDictionary.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 03.07.2026.
//

import FlatBin

public struct PerfectDictionary<Key: RawRepresentable & FlatRawCodable & Sendable & Hashable, Value: FlatCodable & Sendable>: FlatCodable, Sendable
where Key.RawValue: FixedWidthInteger & FlatRawCodable & Sendable {
    @usableFromInline internal var elements: [Key: Value] = [:]
    
    public typealias Storage = PerfectDictionaryStore<Key, Value>.Storage
    public func encode(to storage: inout PerfectDictionaryStore<Key, Value>.Storage, with encoder: borrowing FlatEncoder) {
        PerfectDictionaryStore(elements).encode(to: &storage, with: encoder)
    }
    
    public init(_ elements: [Key: Value]) {
        self.elements = elements
    }
    
    /// Materializes the whole table (`View.load()`). For small tables; the engine's hot paths use `View`.
    public init(pointer: FlatPointer<PerfectDictionaryStore<Key, Value>.Storage>) {
        var elements: [Key: Value] = [:]
        View(pointer: pointer).forEach { entry in
            elements[entry.key.load()] = entry.value.load()
        }
        self.elements = elements
    }
    
    public struct View: FlatView<PerfectDictionary>, ~Escapable {
        @usableFromInline internal let store: PerfectDictionaryStore<Key, Value>.View
        
        @inlinable @inline(always)
        public var pointer: FlatPointer<Storage> {
            @_lifetime(copy self)
            get {
                store.pointer
            }
        }
        
        @inlinable @inline(always)
        @_lifetime(copy pointer)
        public init(pointer: FlatPointer<Storage>) {
            store = .init(pointer: pointer)
        }
    }
    
    @inlinable @inline(always)
    public subscript(_ key: Key) -> Value? {
        get {
            elements[key]
        }
        set {
            elements[key] = newValue
        }
    }
}

@FlatCodable
public struct PerfectDictionaryStore<Key: RawRepresentable & FlatRawCodable & Sendable & Hashable, Value: FlatCodable & Sendable>: Sendable
where Key.RawValue: FixedWidthInteger & FlatRawCodable & Sendable {
    
    @FlatCodable
    public struct Entry: Sendable {
        public let key: Key
        public let value: Value
        
        public init(key: Key, value: Value) {
            self.key = key
            self.value = value
        }
    }

    public let multipliers: [Key.RawValue]
    public let sparseIndices: [UInt16]
    public let denseEntries: [Entry]

    public init(_ dictionary: some Collection<(key: Key, value: Value)>) {
        // Sorted by key so the `.bin` bytes are reproducible.
        let denseList = dictionary
            .map { Entry(key: $0.key, value: $0.value) }
            .sorted { $0.key.rawValue < $1.key.rawValue }
        let (multipliers, table) = build(for: denseList) {$0.key.rawValue}
        denseEntries = denseList
        sparseIndices = table
        self.multipliers = multipliers
    }
    
    @inlinable
    public subscript(_ key: Key) -> Value? {
        guard !denseEntries.isEmpty else { return nil }
        let sparseCount = sparseIndices.count
        let bucketCount = multipliers.count

        let mask = sparseCount - 1
        let shift = Key.RawValue.bitWidth - sparseCount.trailingZeroBitCount
        let bucketMask = bucketCount - 1
        // Arithmetic in the key type, as the table was built: converting to `Int` would trap on 32-bit
        // platforms for keys or multipliers above `Int32.max`.
        let rawKey = key.rawValue
        let bucketIdx = Int(truncatingIfNeeded: rawKey) & bucketMask
        let multiplier = multipliers[bucketIdx]
        let idx = Int(truncatingIfNeeded: (rawKey &* multiplier) >> shift) & mask
        let denseIdx = Int(sparseIndices[idx])
        
        let entry = denseEntries[denseIdx]
        return entry.key == key ? entry.value : nil
    }
}

extension PerfectDictionary: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (Key, Value)...) {
        self.init(Dictionary(uniqueKeysWithValues: elements))
    }
}

extension PerfectDictionary.View {
    @inlinable
    public var count: Int {
        store.count
    }

    @inlinable
    public subscript (key: Key) -> Value.View? {
        @_lifetime(copy self)
        get {
            store[key]
        }
    }
    
    @inlinable
    public func forEach(_ body: ((key: Key.View, value: Value.View)) throws -> Void) rethrows {
        try store.forEach(body)
    }
}


extension PerfectDictionaryStore.View {
    
    @inlinable
    public var count: Int {
        denseEntries.count
    }
    
    @inlinable
    public subscript (key: Key) -> Value.View? {
        @_lifetime(copy self)
        get {
            guard !denseEntries.isEmpty else { return nil }
            let sparseCount = sparseIndices.count
            let bucketCount = multipliers.count

            let mask = sparseCount - 1
            let shift = Key.RawValue.bitWidth - sparseCount.trailingZeroBitCount
            let bucketMask = bucketCount - 1
            // Arithmetic in the key type, as the table was built: converting to `Int` would trap on 32-bit
            // platforms for keys or multipliers above `Int32.max`.
            let rawKey = key.rawValue
            let bucketIdx = Int(truncatingIfNeeded: rawKey) & bucketMask
            let multiplier = multipliers[bucketIdx].load()
            let idx = Int(truncatingIfNeeded: (rawKey &* multiplier) >> shift) & mask
            let denseIdx = Int(sparseIndices[idx].load())
            
            let entry = denseEntries[denseIdx]
            return entry.key.load() == key ? entry.value : nil
        }
    }
    
    @inlinable
    public func forEach(_ body: ((key: Key.View, value: Value.View)) throws -> Void) rethrows {
        try denseEntries.forEach {
            try body((key: $0.key, value: $0.value))
        }
    }
}

extension PerfectDictionary: Sequence {
    public var count: Int {
        elements.count
    }
    public func makeIterator() -> [Key: Value].Iterator {
        elements.makeIterator()
    }
}

extension PerfectDictionaryStore: Sequence {
    @inlinable
    public var count: Int {
        denseEntries.count
    }
    
    @inlinable
    public func makeIterator() -> some IteratorProtocol<(key: Key, value: Value)> {
        denseEntries.map{(key: $0.key, value: $0.value)}.makeIterator()
    }
}
