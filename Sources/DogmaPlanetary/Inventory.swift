//
//  Inventory.swift
//  DogmaPlanetary
//
//  Created by Artem Shimanski on 14.10.2026.
//

/// Pin contents: a short flat array of (typeID, quantity) pairs sorted by typeID. A processor holds at most three
/// entries and a storage a handful, so a dictionary would be pure overhead.
///
/// Zero entries are not stored: `inventory[x] = 0` removes the entry, so `items` shows only what is really there.
public struct Inventory: Hashable, Sendable, Sequence {
    public struct Item: Hashable, Sendable {
        public var typeID: TypeID
        public var quantity: Int

        public init(typeID: TypeID, quantity: Int) {
            self.typeID = typeID
            self.quantity = quantity
        }
    }

    public private(set) var items: [Item] = []

    public init() {}

    /// Items with the same typeID are summed; non-positive quantities are dropped.
    public init(_ items: some Sequence<Item>) {
        for item in items {
            self[item.typeID] += item.quantity
        }
    }

    public var isEmpty: Bool { items.isEmpty }
    public var count: Int { items.count }

    public func makeIterator() -> [Item].Iterator {
        items.makeIterator()
    }

    public subscript(_ typeID: TypeID) -> Int {
        get {
            let index = lowerBound(typeID)
            return index < items.count && items[index].typeID == typeID ? items[index].quantity : 0
        }
        set {
            let index = lowerBound(typeID)
            let exists = index < items.count && items[index].typeID == typeID
            switch (exists, newValue > 0) {
            case (true, true): items[index].quantity = newValue
            case (true, false): items.remove(at: index)
            case (false, true): items.insert(Item(typeID: typeID, quantity: newValue), at: index)
            case (false, false): break
            }
        }
    }

    /// Occupied volume, m3. Commodities unknown to the catalog have no volume (see `Colony.Warning.unknownCommodity`).
    public func volume(in catalog: PlanetaryCatalog) -> Double {
        items.reduce(0) { $0 + Double($1.quantity) * (catalog.commodity($1.typeID)?.volume ?? 0) }
    }

    private func lowerBound(_ typeID: TypeID) -> Int {
        var low = 0
        var high = items.count
        while low < high {
            let mid = (low + high) / 2
            if items[mid].typeID.rawValue < typeID.rawValue { low = mid + 1 } else { high = mid }
        }
        return low
    }
}
