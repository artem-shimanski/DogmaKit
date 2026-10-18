//
//  PerfectSet.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 03.07.2026.
//

import FlatBin

public struct PerfectSet<Element: RawRepresentable & FlatRawCodable & Sendable & Hashable>: FlatCodable, Sendable
where Element.RawValue: FixedWidthInteger & FlatRawCodable & Sendable {
    @usableFromInline internal var elements: Set<Element> = []
    
    public typealias Storage = PerfectSetStore<Element>.Storage
    public func encode(to storage: inout PerfectSetStore<Element>.Storage, with encoder: borrowing FlatEncoder) {
        PerfectSetStore(elements).encode(to: &storage, with: encoder)
    }
    
    public init(_ elements: Set<Element>) {
        self.elements = elements
    }
    
    public init(pointer: FlatPointer<PerfectSetStore<Element>.Storage>) {
        let denseEntries = Array(pointer: pointer[\.denseEntries])
        self.elements = Set(denseEntries)
    }
    
    public struct View: FlatView<PerfectSet>, ~Escapable {
        @usableFromInline internal let store: PerfectSetStore<Element>.View
        
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
}

@FlatCodable
public struct PerfectSetStore<Element: RawRepresentable & FlatRawCodable & Sendable & Hashable>: Sendable
where Element.RawValue: FixedWidthInteger & FlatRawCodable & Sendable {
    
    public let multipliers: [Element.RawValue]
    public let sparseIndices: [UInt16]
    public let denseEntries: [Element]

    public init(_ elements: some Collection<Element>) {
        // Sorted so the bytes are reproducible.
        let denseList = elements.sorted { $0.rawValue < $1.rawValue }
        let (multipliers, table) = build(for: denseList) {$0.rawValue}
        denseEntries = denseList
        sparseIndices = table
        self.multipliers = multipliers
    }
    
    @inlinable
    public func contains(_ element: Element) -> Bool {
        guard !denseEntries.isEmpty else { return false }
        let sparseCount = sparseIndices.count
        let bucketCount = multipliers.count

        let mask = sparseCount - 1
        let shift = Element.RawValue.bitWidth - sparseCount.trailingZeroBitCount
        let bucketMask = bucketCount - 1
        let iKey = Int(element.rawValue)
        
        let bucketIdx = iKey & bucketMask
        
        let multiplier = Int(multipliers[bucketIdx])
        
        let idx = ((iKey &* multiplier) >> shift) & mask
        let denseIdx = Int(sparseIndices[idx])
        
        let entry = denseEntries[denseIdx]
        return entry == element
    }
    
    @inlinable
    public func forEach(_ body: (Element) throws -> Void) rethrows {
        try denseEntries.forEach {
            try body($0)
        }
    }

}

extension PerfectSet: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: (Element)...) {
        self.init(Set(elements))
    }
}

extension PerfectSet.View {
    @inlinable
    public var count: Int {
        store.count
    }

    @inlinable
    public func contains(_ element: Element) -> Bool {
        store.contains(element)
    }
    
    @inlinable
    public func forEach(_ body: (Element.View) throws -> Void) rethrows {
        try store.forEach(body)
    }
}

extension PerfectSetStore.View {
    
    @inlinable
    public var count: Int {
        denseEntries.count
    }
    
    @inlinable
    public func contains(_ element: Element) -> Bool {
        guard !denseEntries.isEmpty else { return false }
        let sparseCount = sparseIndices.count
        let bucketCount = multipliers.count
        
        let mask = sparseCount - 1
        let shift = Element.RawValue.bitWidth - sparseCount.trailingZeroBitCount
        let bucketMask = bucketCount - 1
        let iKey = Int(element.rawValue)
        
        let bucketIdx = iKey & bucketMask
        
        let multiplier = Int(multipliers[bucketIdx].load())
        
        let idx = ((iKey &* multiplier) >> shift) & mask
        let denseIdx = Int(sparseIndices[idx].load())
        
        let entry = denseEntries[denseIdx]
        return entry.load() == element
    }
    
    @inlinable
    public func forEach(_ body: (Element.View) throws -> Void) rethrows {
        try denseEntries.forEach {
            try body($0)
        }
    }
}
