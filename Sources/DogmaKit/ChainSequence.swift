//
//  ChainSequence.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 10.07.2026.
//


@frozen
public struct ChainSequence<First: Sequence, Second: Sequence>: Sequence where First.Element == Second.Element {
    public typealias Element = First.Element
    
    @usableFromInline let first: First
    @usableFromInline let second: Second
    
    @inlinable
    public init(_ first: First, _ second: Second) {
        self.first = first
        self.second = second
    }
    
    @frozen
    public struct Iterator: IteratorProtocol {
        @usableFromInline var firstIterator: First.Iterator?
        @usableFromInline var secondIterator: Second.Iterator
        
        @inlinable
        init(first: First, second: Second) {
            self.firstIterator = first.makeIterator()
            self.secondIterator = second.makeIterator()
        }
        
        @inlinable
        public mutating func next() -> Element? {
            if let element = firstIterator?.next() {
                return element
            }
            firstIterator = nil
            return secondIterator.next()
        }
    }
    
    @inlinable
    public func makeIterator() -> Iterator {
        return Iterator(first: first, second: second)
    }
}

extension Sequence {
    @inlinable
    public func chained<Other: Sequence>(with other: Other) -> ChainSequence<Self, Other> where Other.Element == Self.Element {
        return ChainSequence(self, other)
    }
}
