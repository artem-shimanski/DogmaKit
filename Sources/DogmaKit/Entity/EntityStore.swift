//
//  EntityStore.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 22.06.2026.
//

import BitField
import DogmaModels

extension UInt16 {
    @usableFromInline static var invalid: Self {.max}
}

@usableFromInline
struct EntityStore: Sendable {
    @usableFromInline struct Node: BitwiseCopyable, Sendable {
        @usableFromInline var next: EntityID = .invalid
        @usableFromInline var prev: EntityID = .invalid
        @usableFromInline var valueIndex: UInt16 = .invalid
    }
    @usableFromInline internal var nodes: ContiguousArray<Node> = []
    @usableFromInline internal var values: ContiguousArray<Entity> = []
    @usableFromInline internal var allocators: ContiguousArray<Allocator>
    @usableFromInline internal var mutations: [EntityID: [Mutation.Roll]] = [:]

    private mutating func initialize(bits: BitMask<UInt16>, allocator: EntityID) {
        var id = allocator
        id[bits] = 1
        allocators[Int(allocator.allocatorID)].freeHead = id
        for _ in 1..<bits.maxValue {
            let current = id
            id[bits] &+= 1
            nodes[Int(current.rawValue)].next = id
        }
    }
    
    @usableFromInline struct Allocator: BitwiseCopyable, Sendable {
        @usableFromInline var freeHead: EntityID = .invalid
        @usableFromInline var activeTail: EntityID = .invalid
        @usableFromInline var activeHead: EntityID = .invalid
    }

    init() {
        self.values.reserveCapacity(1000)
        self.allocators = ContiguousArray(repeating: Allocator(), count: Int(EntityID.$allocatorBits.maxValue) + 1)
        self.nodes = ContiguousArray(repeating: Node(), count: Int(EntityID.RawValue.max) + 1)
        
        initialize(bits: EntityID.$pilotID, allocator: .gang)
        // Environment entities live under "pilot 0" (see `EntityID.environment`); real
        // pilots are numbered from 1.
        initialize(bits: EntityID.$rawID, allocator: EntityID.environment())

        for i in 1...EntityID.$pilotID.maxValue {
            let pilot = EntityID.pilot(UInt8(i))
            let hull = EntityID.hull(for: pilot)

            initialize(bits: EntityID.$rawID, allocator: EntityID.skill(for: pilot))
            initialize(bits: EntityID.$rawID, allocator: EntityID.implant(for: pilot))
            initialize(bits: EntityID.$rawID, allocator: EntityID.booster(for: pilot))

            for slot in Entity.Module.Slot.allCases {
                initialize(bits: EntityID.$moduleID, allocator: EntityID.module(in: slot, on: hull))
            }
            for squadron in Entity.Drone.Squadron.allCases {
                initialize(bits: EntityID.$droneID, allocator: EntityID.drone(in: squadron, on: hull))
            }
            initialize(bits: EntityID.$rawID, allocator: EntityID.cargo(on: hull))
        }
    }
    
    @inlinable var count: Int {
        values.count
    }
    
    @discardableResult @inlinable
    mutating func append(in allocator: EntityID, _ initialize: (EntityID) -> Entity) throws(DogmaError) -> EntityID {
        let allocatorID = Int(allocator.allocatorID)
        var allocator = allocators[allocatorID]
        let allocatedIndex = allocator.freeHead
        
        guard allocatedIndex != .invalid else {throw DogmaError.entityLimitExceeded }
        let idx = Int(allocatedIndex.rawValue)
        
        allocator.freeHead = nodes[Int(allocatedIndex.rawValue)].next
        
        nodes[idx].next = .invalid
        nodes[idx].prev = allocator.activeTail
        
        if allocator.activeTail != .invalid {
            nodes[Int(allocator.activeTail.rawValue)].next = allocatedIndex
        } else {
            allocator.activeHead = allocatedIndex
        }
        allocator.activeTail = allocatedIndex
        allocators[allocatorID] = allocator

        let entity = initialize(allocatedIndex)
        assert(entity.id == allocatedIndex)
        values.append(entity)
        nodes[idx].valueIndex = UInt16(values.count - 1)

        return allocatedIndex
    }
    
    @inlinable
    mutating func remove(_ id: EntityID) {
        guard id != .invalid else {return}

        let sparseIdx = Int(id.rawValue)
        let currentDenseIdx = nodes[sparseIdx].valueIndex
        guard currentDenseIdx != .invalid else {return}
        let lastDenseIdx = values.count - 1
        
        if currentDenseIdx != lastDenseIdx {
            let lastValue = values[lastDenseIdx]
            values[Int(currentDenseIdx)] = lastValue
            nodes[Int(lastValue.id.rawValue)].valueIndex = currentDenseIdx
        }
        values.removeLast()
        nodes[sparseIdx].valueIndex = .invalid

        // Charges are not in allocator lists (stored via subscript, not `append(in:)`), so
        // the slot's list pointers must not be touched.
        if id.isCharge {
            mutations[id] = nil
            return
        }

        var allocator = allocators[Int(id.allocatorID)]
        
        let prevIndex = nodes[sparseIdx].prev
        let nextIndex = nodes[sparseIdx].next
        
        if prevIndex != .invalid {
            nodes[Int(prevIndex.rawValue)].next = nextIndex
        }
        else {
            allocator.activeHead = nextIndex
        }
        
        if nextIndex != .invalid {
            nodes[Int(nextIndex.rawValue)].prev = prevIndex
        }
        else {
            allocator.activeTail = prevIndex
        }
        
        nodes[sparseIdx].next = allocator.freeHead
        nodes[sparseIdx].prev = .invalid
        allocator.freeHead = id
        allocators[Int(id.allocatorID)] = allocator
        
        mutations[id] = nil
    }
    
    @usableFromInline
    mutating func removeAll(in entity: EntityID) {
        var left = 0
        var right = values.count - 1
        let hasMutations = !mutations.isEmpty

        while left <= right {
            if entity.isParent(of: values[left].id) {
                while left <= right && entity.isParent(of: values[right].id) {
                    let id = values[right].id
                    nodes[Int(id.rawValue)].valueIndex = .invalid
                    if hasMutations { mutations[id] = nil }
                    right -= 1
                }
                guard left < right else { break }

                let id = values[left].id
                nodes[Int(id.rawValue)].valueIndex = .invalid
                if hasMutations { mutations[id] = nil }

                let lastValue = values[right]
                values[left] = lastValue
                nodes[Int(lastValue.id.rawValue)].valueIndex = UInt16(left)
                right -= 1
            }
            left += 1
        }

        values.removeLast(values.count - (right + 1))
        
        func clearHull(_ hull: EntityID) {
            for slot in Entity.Module.Slot.allCases {
                clear(allocator: .module(in: slot, on: hull))
            }
            for squadron in Entity.Drone.Squadron.allCases {
                clear(allocator: .drone(in: squadron, on: hull))
            }
            clear(allocator: .cargo(on: hull))
        }
        
        switch entity.category {
        case .hull:
            clearHull(entity)
        case .pilot:
            clear(allocator: .skill(for: entity))
            clear(allocator: .implant(for: entity))
            clear(allocator: .booster(for: entity))
            clearHull(.hull(for: entity))
        default:
            clear(allocator: entity)
        }
    }
    
    mutating private func clear(allocator: EntityID) {
        let id = Int(allocator.allocatorID)
        let activeHead = allocators[id].activeHead
        guard activeHead != .invalid else {return}

        nodes[Int(allocators[id].activeTail.rawValue)].next = allocators[id].freeHead
        allocators[id].freeHead = activeHead
        allocators[id].activeHead = .invalid
        allocators[id].activeTail = .invalid
    }
    
    /// Mutation rolls of the entity, sorted by `attributeID.rawValue`. `nil` if the entity
    /// is not mutated.
    @inlinable
    func rolls(for id: EntityID) -> [Mutation.Roll]? {
        mutations[id]
    }

    /// Replaces the entity's rolls. An empty array removes the entry.
    @inlinable
    mutating func setRolls(_ rolls: [Mutation.Roll], for id: EntityID) {
        if rolls.isEmpty {
            mutations[id] = nil
        } else {
            mutations[id] = rolls
        }
    }

    @inlinable
    subscript(_ id: EntityID) -> Entity? {
        get {
            let sparseIdx = Int(id.rawValue)

            let denseIdx = nodes[sparseIdx].valueIndex
            guard denseIdx != .invalid else { return nil }
            
            return values[Int(denseIdx)]
        }
        set {
            if let newValue {
                let sparseIdx = Int(id.rawValue)

                let denseIdx = nodes[sparseIdx].valueIndex
                if denseIdx == .invalid {
                    let newDenseIdx = UInt16(values.count)
                    nodes[sparseIdx].valueIndex = newDenseIdx
                    values.append(newValue)
                }
                else {
                    values[Int(denseIdx)] = newValue
                }
            }
            else {
                switch id.category {
                case .pilot, .hull:
                    removeAll(in: id)
                default:
                    remove(id)
                }
            }
        }
    }
    
    @inlinable
    func contains(_ id: EntityID) -> Bool {
        let sparseIdx = Int(id.rawValue)
        let denseIdx = nodes[sparseIdx].valueIndex
        return denseIdx != .invalid
    }
    
    @inlinable
    func index(of id: EntityID) -> UInt16? {
        let sparseIdx = Int(id.rawValue)
        let denseIdx = nodes[sparseIdx].valueIndex
        return denseIdx != .invalid ? denseIdx : nil
    }
    
    
    @inlinable
    func allocator(for id: EntityID) -> Allocator {
        allocators[Int(id.allocatorID)]
    }

    @inlinable
    func ids(in allocator: EntityID) -> EntityIDEnumerator {
        let head = allocators[Int(allocator.allocatorID)].activeHead
        return EntityIDEnumerator(head: head, nodes: nodes)
    }

    @inlinable
    func modules(on hull: EntityID) -> ModuleSequence {
        ModuleSequence(store: self, hull: hull)
    }

    @inlinable
    func drones(on hull: EntityID) -> DroneSequence {
        DroneSequence(store: self, hull: hull)
    }

    @inlinable
    func charges(on hull: EntityID) -> some Sequence<EntityID> {
        ChargeSequence(base: modules(on: hull).chained(with: drones(on: hull)), store: self)
    }
    
    @inlinable
    func hulls() -> HullSequence {
        HullSequence(store: self)
    }
    
    @inlinable
    borrowing func forEach(in allocator: EntityID, _ body: (EntityID) -> Void) {
        var next = self.allocator(for: allocator).activeHead
        while next != .invalid {
            let id = next
            next = nodes[Int(next.rawValue)].next
            body(id)
        }
    }
    
    @inlinable
    func forEachModule(on hull: EntityID, _ body: (EntityID) -> Void) {
        for slot in Entity.Module.Slot.allCases {
            forEach(in: .module(in: slot, on: hull), body)
        }
    }

    @inlinable
    func forEachCharge(on hull: EntityID, _ body: (EntityID) -> Void) {
        forEachModule(on: hull) { moduleID in
            let charge = EntityID.charge(in: moduleID)
            if self.contains(charge) {
                body(charge)
            }
        }
    }
}

extension EntityStore: Sequence {
    @inlinable
    func makeIterator() -> ContiguousArray<Entity>.Iterator {
        values.makeIterator()
    }
}


@usableFromInline
struct EntityIDEnumerator: Sequence {
    @usableFromInline let head: EntityID
    @usableFromInline let nodes: ContiguousArray<EntityStore.Node>
    
    @inlinable
    init(head: EntityID, nodes: ContiguousArray<EntityStore.Node>) {
        self.head = head
        self.nodes = nodes
    }
    
    @inlinable
    func makeIterator() -> Iterator {
        Iterator(id: head, nodes: nodes)
    }
    
    @usableFromInline
    struct Iterator: IteratorProtocol {
        @usableFromInline var id: EntityID
        @usableFromInline var nodes: ContiguousArray<EntityStore.Node>
        
        @inlinable
        init(id: EntityID, nodes: ContiguousArray<EntityStore.Node>) {
            self.id = id
            self.nodes = nodes
        }
        
        @inlinable
        mutating func next() -> EntityID? {
            guard id != .invalid else {return nil}
            let current = id
            id = nodes[Int(id.rawValue)].next
            return current
        }
    }
}

@usableFromInline
struct ModuleSequence: Sequence {
    @usableFromInline let store: EntityStore
    @usableFromInline let hull: EntityID
    
    @inlinable
    init(store: EntityStore, hull: EntityID) {
        self.store = store
        self.hull = hull
    }
    
    @inlinable
    func makeIterator() -> Iterator {
        Iterator(store: store, hull: hull)
    }
    
    @usableFromInline
    struct Iterator: IteratorProtocol {
        @usableFromInline let store: EntityStore
        @usableFromInline let hull: EntityID
        @usableFromInline var slotIterator: Entity.Module.Slot.AllCases.Iterator
        @usableFromInline var moduleIterator: EntityIDEnumerator.Iterator?
        
        @inlinable
        init(store: EntityStore, hull: EntityID) {
            self.store = store
            self.hull = hull
            slotIterator = Entity.Module.Slot.allCases.makeIterator()
        }
        
        @inlinable
        mutating func next() -> EntityID? {
            while true {
                if let id = moduleIterator?.next() {
                    return id
                }
                else if let slot = slotIterator.next() {
                    moduleIterator = store.ids(in: .module(in: slot, on: hull)).makeIterator()
                }
                else {
                    return nil
                }
            }
        }
    }
}

@usableFromInline
struct DroneSequence: Sequence {
    @usableFromInline let store: EntityStore
    @usableFromInline let hull: EntityID
    
    @inlinable
    init(store: EntityStore, hull: EntityID) {
        self.store = store
        self.hull = hull
    }
    
    @inlinable
    func makeIterator() -> Iterator {
        Iterator(store: store, hull: hull)
    }
    
    @usableFromInline
    struct Iterator: IteratorProtocol {
        @usableFromInline let store: EntityStore
        @usableFromInline let hull: EntityID
        @usableFromInline var squadronIterator: Entity.Drone.Squadron.AllCases.Iterator
        @usableFromInline var droneIterator: EntityIDEnumerator.Iterator?
        
        @inlinable
        init(store: EntityStore, hull: EntityID) {
            self.store = store
            self.hull = hull
            squadronIterator = Entity.Drone.Squadron.allCases.makeIterator()
        }
        
        @inlinable
        mutating func next() -> EntityID? {
            while true {
                if let id = droneIterator?.next() {
                    return id
                }
                else if let squadron = squadronIterator.next() {
                    droneIterator = store.ids(in: .drone(in: squadron, on: hull)).makeIterator()
                }
                else {
                    return nil
                }
            }
        }
    }
}

@usableFromInline
struct ChargeSequence<Base: Sequence<EntityID>>: Sequence {
    @usableFromInline let base: Base
    @usableFromInline let store: EntityStore
    
    @inlinable
    init(base: Base, store: EntityStore) {
        self.base = base
        self.store = store
    }
    
    @inlinable
    func makeIterator() -> Iterator {
        Iterator(base: base.makeIterator(), store: store)
    }
    
    @usableFromInline
    struct Iterator: IteratorProtocol {
        @usableFromInline var base: Base.Iterator
        @usableFromInline var store: EntityStore
        
        @inlinable
        init(base: Base.Iterator, store: EntityStore) {
            self.store = store
            self.base = base
        }
        
        @inlinable
        mutating func next() -> EntityID? {
            while let id = base.next() {
                let chargeID = EntityID.charge(in: id)
                if store.contains(chargeID) {
                    return chargeID
                }
            }
            return nil
        }
    }
}

@usableFromInline
struct HullSequence: Sequence {
    @usableFromInline let store: EntityStore
    
    @inlinable
    init(store: EntityStore) {
        self.store = store
    }
    
    @inlinable
    func makeIterator() -> Iterator {
        Iterator(pilots: store.ids(in: .pilot()).makeIterator())
    }
    
    @usableFromInline
    struct Iterator: IteratorProtocol {
        @usableFromInline var pilots: EntityIDEnumerator.Iterator
        
        @inlinable
        init(pilots: EntityIDEnumerator.Iterator) {
            self.pilots = pilots
        }
        
        @inlinable
        mutating func next() -> EntityID? {
            guard let id = pilots.next() else {return nil}
            return EntityID.hull(for: id)
        }
    }
}
