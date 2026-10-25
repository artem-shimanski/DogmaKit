//
//  AttributeRegistry.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 12.07.2026.
//

import DogmaModels
import BitField

extension AttributeKey {
    @inlinable
    var hash: Int32 {
        let a = Int32(attributeID.rawValue)
        return (a ^ (a >> 8))
    }
}

@usableFromInline let initialBucketSize: Int32 = 512
@usableFromInline let initialBucketMask = initialBucketSize - 1

@usableFromInline
struct AttributeRegistry<Value: Sendable>: Sendable {
    
    @usableFromInline struct Node: Sendable {
        @usableFromInline var key: AttributeKey = AttributeKey(rawValue: 0)
        @usableFromInline var index: Int32 = -1
        
        @inlinable
        init(key: AttributeKey = .init(rawValue: 0), index: Int32 = -1) {
            self.key = key
            self.index = index
        }
        
        @inlinable
        var isEmpty: Bool {
            index == -1
        }
        
        @inlinable
        var isDeleted: Bool {
            get { index == .max }
            set { index = .max }
        }
    }
    
    @usableFromInline struct Entry: Sendable {
        @usableFromInline var sparseIndex: Int32
        @usableFromInline var value: Value
        
        @inlinable
        init(sparseIndex: Int32, value: Value) {
            self.sparseIndex = sparseIndex
            self.value = value
        }
    }
    
    @usableFromInline struct Bucket: Sendable {
        @usableFromInline var offset: Int32 = -1
        @usableFromInline var mask: Int32 = 0
        @usableFromInline var count: Int32 = 0
        @usableFromInline var size: Int32 = 0
        
        @inlinable
        init(offset: Int32 = -1, mask: Int32 = 0, count: Int32 = 0, size: Int32 = 0) {
            self.offset = offset
            self.mask = mask
            self.count = count
            self.size = size
        }
    }
    
    @usableFromInline var buckets: ContiguousArray<Bucket>
    @usableFromInline var keys: ContiguousArray<Node> = []
    @usableFromInline var values: ContiguousArray<Entry> = []
    
    @inlinable
    init() {
        buckets = .init(repeating: Bucket(), count: Int(EntityID.RawValue.max))
    }
    
    /// Clears all contents and lays out buckets for the current set of entities. Must be
    /// called before any lookup or insert in a new pass: accessing an entity without a
    /// bucket crashes.
    @inlinable
    mutating func reset(for entities: borrowing EntityStore) {
        let count = entities.count
        let keysCount = count * Int(initialBucketSize)
        let valuesCount = count * 20
        
        values.removeAll(keepingCapacity: true)
        keys.removeAll(keepingCapacity: true)
        
        keys.reserveCapacity(keysCount + Int(initialBucketSize) * 20)
        keys.append(addingCapacity: keysCount) { span in
            span.withUnsafeMutableBufferPointer { buffer, initializedCount in
                buffer.initialize(repeating: Node())
                initializedCount = buffer.count
            }
        }
        
        var offset: Int32 = 0
        for entity in entities {
            self[bucket: entity.id] = Bucket(offset: offset, mask: initialBucketMask, count: 0, size: initialBucketSize)
            offset += initialBucketSize
        }
        
        if valuesCount > values.capacity {
            values.reserveCapacity(valuesCount)
        }
    }
    
    @inlinable
    subscript(bucket id: EntityID) -> Bucket {
        get {
            buckets[Int(id.rawValue)]
        }
        set {
            buckets[Int(id.rawValue)] = newValue
        }
    }
    
    @inlinable
    var isEmpty: Bool {
        values.isEmpty
    }

    @usableFromInline
    enum Lookup {
        case found(valueIndex: Int32, keyIndex: Int)
        case emptySlot(keyIndex: Int)
    }
    
    @inlinable
    func lookup(forKey key: AttributeKey) -> Lookup {
        let bucket = self[bucket: key.entityID]

        let hash = key.hash
        var firstDeleted: Int?
        
        var localIdx = hash & bucket.mask
        
        while true {
            let idx = Int(bucket.offset + localIdx)
            let node = keys[idx]
            if node.isEmpty {
                return .emptySlot(keyIndex: firstDeleted ?? idx)
            }
            else if node.isDeleted {
                if firstDeleted == nil {
                    firstDeleted = idx
                }
            }
            else if node.key == key{
                return .found(valueIndex: node.index, keyIndex: idx)
            }
            
            localIdx = (localIdx + 1) & bucket.mask
        }
    }

    @inlinable
    mutating func insert(_ newElement: Value, forKey key: AttributeKey, at keyIndex: Int) {
        var keyIndex = keyIndex
        while true {
            let bucketID = key.entityID
            let bucket = self[bucket: bucketID]
            let maxElements = (bucket.size >> 1) + (bucket.size >> 2)
            if bucket.count >= maxElements {
                resize(bucket: bucketID)
                switch lookup(forKey: key) {
                case let .emptySlot(keyIndex: idx):
                    keyIndex = idx
                default:
                    fatalError()
                }
            }
            else {
                keys[keyIndex] = .init(key: key, index: Int32(values.count))
                values.append(Entry(sparseIndex: Int32(keyIndex), value: newElement))
                self[bucket: bucketID].count += 1
                return
            }
        }
    }
    
    @inlinable
    mutating func remove(at keyIndex: Int) {
        let value = keys[keyIndex].index
        let lastIDx = values.count - 1
        if lastIDx != value {
            keys[Int(values[lastIDx].sparseIndex)].index = Int32(value)
            values[Int(value)] = values[lastIDx]
        }
        values.removeLast()
        keys[keyIndex].isDeleted = true
    }
    
    @inlinable
    subscript(key: AttributeKey) -> Value? {
        get {
            switch lookup(forKey: key) {
            case let .found(value, _): return values[Int(value)].value
            default: return nil
            }
        }
        set {
            switch lookup(forKey: key) {
            case let .found(valueIdx, keyIdx):
                if let newValue {
                    values[Int(valueIdx)].value = newValue
                }
                else {
                    remove(at: keyIdx)
                }
            case let .emptySlot(keyIndex: keyIdx):
                guard let newValue else {return}
                insert(newValue, forKey: key, at: keyIdx)
            }
        }
    }
    
    @inlinable
    var last: (key: AttributeKey, value: Value)? {
        guard let node = values.last else {return nil}
        return (key: keys[Int(node.sparseIndex)].key, value: node.value)
    }
    
    @inlinable
    mutating func resize(bucket: EntityID) {
        let currentBucket = self[bucket: bucket]

        let newBucket = Bucket(offset: Int32(keys.count),
                               mask: (currentBucket.mask << 1) | 1,
                               count: currentBucket.count,
                               size: currentBucket.size * 2)
        self[bucket: bucket] = newBucket
        keys.append(contentsOf: repeatElement(Node(), count: Int(newBucket.size)))

        let offset = Int(currentBucket.offset)
        for idx in offset..<(offset + Int(currentBucket.size)) {
            let node = keys[idx]
            if !node.isEmpty && !node.isDeleted {
                switch lookup(forKey: node.key) {
                case let .emptySlot(keyIdx):
                    values[Int(node.index)].sparseIndex = Int32(keyIdx)
                    keys[keyIdx] = .init(key: node.key, index: node.index)
                default:
                    fatalError()
                }
            }
        }
    }
}

extension AttributeRegistry {
    /// Iterates the values stored for one entity, in bucket order. The entity must have a
    /// bucket in the current pass (see `reset(for:)`).
    @inlinable
    func forEach(in entityID: EntityID, _ body: (AttributeID, Value) -> Void) {
        let bucket = self[bucket: entityID]
        guard bucket.offset >= 0 else { return }
        let offset = Int(bucket.offset)
        for idx in offset..<(offset + Int(bucket.size)) {
            let node = keys[idx]
            guard !node.isEmpty && !node.isDeleted else { continue }
            body(node.key.attributeID, values[Int(node.index)].value)
        }
    }
}

extension AttributeRegistry: Sequence {
    @usableFromInline
    struct Iterator: IteratorProtocol {
        @usableFromInline var keys: ContiguousArray<Node> = []
        @usableFromInline var i: ContiguousArray<Entry>.Iterator
        
        @inlinable
        mutating func next() -> (key: AttributeKey, value: Value)? {
            guard let node = i.next() else {return nil}
            let key = keys[Int(node.sparseIndex)].key
            return (key: key, value: node.value)
        }
    }

    @usableFromInline
    func makeIterator() -> Iterator {
        Iterator(keys: keys, i: values.makeIterator())
    }
}
