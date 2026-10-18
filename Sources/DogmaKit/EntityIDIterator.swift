//
//  ItemIDIterator.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 18.06.2026.
//

import BitField
import FlatBin

@frozen
@usableFromInline
enum EitherSequence<A: Sequence, B: Sequence>: Sequence where A.Element == B.Element {
    case left(A)
    case right(B)
    
    @frozen
    @usableFromInline
    enum Iterator: IteratorProtocol {
        case left(A.Iterator)
        case right(B.Iterator)
        
        @inlinable
        mutating func next() -> A.Element? {
            switch self {
            case var .left(left):
                let result = left.next()
                self = .left(left)
                return result
            case var .right(right):
                let result = right.next()
                self = .right(right)
                return result
            }
        }
    }
    
    @inlinable
    func makeIterator() -> Iterator {
        switch self {
        case let .left(left): return .left(left.makeIterator())
        case let .right(right): return .right(right.makeIterator())
        }
    }
}

@resultBuilder
@usableFromInline
struct SequenceBuilder<Element> {
    @inlinable
    static func buildExpression(_ expression: Element) -> CollectionOfOne<Element> {
        CollectionOfOne(expression)
    }
    
    @inlinable
    static func buildExpression<S: Sequence>(_ expression: S) -> S where S.Element == Element {
        expression
    }

    @inlinable
    static func buildBlock() -> EmptyCollection<Element> {
        EmptyCollection()
    }

    @inlinable
    static func buildBlock<S: Sequence>(_ component: S) -> S where S.Element == Element {
        component
    }

    @inlinable
    static func buildEither<First: Sequence, Second: Sequence>(first component: First) -> EitherSequence<First, Second> {
        .left(component)
    }

    @inlinable
    static func buildEither<First: Sequence, Second: Sequence>(second component: Second) -> EitherSequence<First, Second> {
        .right(component)
    }
    
    @inlinable
    static func buildOptional<S: Sequence>(_ component: S?) -> EitherSequence<S, EmptyCollection<Element>> where S.Element == Element {
        if let component = component {
            return .left(component)
        } else {
            return .right(EmptyCollection())
        }
    }
}


@usableFromInline
struct LocationGroupFilter<Base: Sequence<EntityID>>: Sequence {
    @usableFromInline var base: Base
    @usableFromInline var groupID: GroupID
    @usableFromInline var entities: EntityStore
    
    @inlinable
    init(base: Base, groupID: GroupID, entities: EntityStore) {
        self.base = base
        self.groupID = groupID
        self.entities = entities
    }
    
    @inlinable
    func makeIterator() -> Iterator {
        Iterator(base: base.makeIterator(), groupID: groupID, entities: entities)
    }
    
    @usableFromInline
    struct Iterator: IteratorProtocol {
        @usableFromInline var base: Base.Iterator
        @usableFromInline var groupID: GroupID
        @usableFromInline var entities: EntityStore
        
        @inlinable
        init(base: Base.Iterator, groupID: GroupID, entities: EntityStore) {
            self.base = base
            self.groupID = groupID
            self.entities = entities
        }
        
        @inlinable
        mutating func next() -> EntityID? {
            while let id = base.next() {
                if entities[id]?.groupID == groupID {
                    return id
                }
            }
            return nil
        }
    }
}

extension Sequence where Element == EntityID {
    @inlinable
    func locationGroup(_ groupID: GroupID, from entities: EntityStore) -> LocationGroupFilter<Self>  {
        LocationGroupFilter(base: self, groupID: groupID, entities: entities)
    }
}

@usableFromInline
struct LocationRequiredSkillFilter<Base: Sequence<EntityID>>: Sequence {
    @usableFromInline var base: Base
    @usableFromInline var skillID: TypeID
    @usableFromInline var entities: EntityStore
    @usableFromInline var sde: SDE
    
    @inlinable
    init(base: Base, skillID: TypeID, entities: EntityStore, sde: SDE) {
        self.base = base
        self.skillID = skillID
        self.entities = entities
        self.sde = sde
    }
    
    @inlinable
    func makeIterator() -> Iterator {
        Iterator(base: base.makeIterator(), skillID: skillID, entities: entities, sde: sde)
    }
    
    @usableFromInline
    struct Iterator: IteratorProtocol {
        @usableFromInline var base: Base.Iterator
        @usableFromInline var skillID: TypeID
        @usableFromInline var entities: EntityStore
        @usableFromInline var sde: SDE

        @inlinable
        init(base: Base.Iterator, skillID: TypeID, entities: EntityStore, sde: SDE) {
            self.base = base
            self.skillID = skillID
            self.entities = entities
            self.sde = sde
        }
        
        @inlinable
        mutating func next() -> EntityID? {
            while let id = base.next() {
                let info = sde[entities[id]!.info]
                if info.requiredSkills.contains(skillID) {
                    return id
                }
            }
            return nil
        }
    }
}

extension Sequence where Element == EntityID {
    @inlinable
    func locationRequiredSkill(_ skillID: TypeID, from entities: EntityStore, using sde: SDE) -> LocationRequiredSkillFilter<Self>  {
        LocationRequiredSkillFilter(base: self, skillID: skillID, entities: entities, sde: sde)
    }
}


@usableFromInline
enum EntityIDSequece: Sequence {
    case empty
    case one(EntityID)
    case enumerator(EntityIDEnumerator)
    case hulls(HullSequence)
    
    @usableFromInline typealias Element = EntityID
    
    @inlinable
    func makeIterator() -> Iterator {
        switch self {
        case .empty: return .empty
        case let .one(id): return .one(id)
        case let .enumerator(base): return .enumerator(base.makeIterator())
        case let .hulls(base): return .hulls(base.makeIterator())
        }
    }
    
    @usableFromInline
    enum Iterator: IteratorProtocol {
        case empty
        case one(EntityID)
        case enumerator(EntityIDEnumerator.Iterator)
        case hulls(HullSequence.Iterator)

        @inlinable
        mutating func next() -> Element? {
            switch self {
            case .empty: return nil
            case let .one(id):
                self = .empty
                return id
            case var .enumerator(iterator):
                if let id = iterator.next() {
                    self = .enumerator(iterator)
                    return id
                }
                else {
                    self = .empty
                    return nil
                }
            case var .hulls(iterator):
                if let id = iterator.next() {
                    self = .hulls(iterator)
                    return id
                }
                else {
                    self = .empty
                    return nil
                }
            }
        }
    }
}

@usableFromInline
struct CastEntityIDSequence<Base: Sequence, Element: RawRepresentable>: Sequence where Base.Element == EntityID, Element.RawValue == EntityID {
    @usableFromInline let base: Base
    
    @inlinable
    init(base: Base) {
        self.base = base
    }
    
    @inlinable
    func makeIterator() -> Iterator {
        Iterator(base: base.makeIterator())
    }
    
    @usableFromInline
    struct Iterator: IteratorProtocol {
        @usableFromInline var base: Base.Iterator
        
        @inlinable
        init(base: Base.Iterator) {
            self.base = base
        }
        
        @inlinable
        mutating func next() -> Element? {
            guard let id = base.next() else { return nil }
            return Element(rawValue: id)
        }
    }
}

extension Sequence where Element == EntityID {
    @inlinable
    func `as`<T: RawRepresentable>(_ type: T.Type) -> CastEntityIDSequence<Self, T> where T.RawValue == EntityID {
        CastEntityIDSequence(base: self)
    }
}
