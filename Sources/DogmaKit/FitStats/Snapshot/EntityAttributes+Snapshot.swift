//
//  EntityAttributes+Snapshot.swift
//  DogmaKit
//

extension EntityAttributes {

    /// Calculated attributes of one entity, copied out of the engine and sorted by ID.
    ///
    /// Opt-in: node snapshots (`FitStats.Module.Snapshot` and others) do not include
    /// attributes, since copying all of them on every read is rarely needed. Lookup is a
    /// binary search. SDE defaults are read from the SDE itself, which is immutable, so
    /// holding it does not pin any engine buffer.
    public struct Snapshot: Sendable, Equatable, Sequence {
        public let attributeIDs: [AttributeID]
        public let values: [Double]
        let sde: SDE

        init(attributeIDs: [AttributeID], values: [Double], sde: SDE) {
            self.attributeIDs = attributeIDs
            self.values = values
            self.sde = sde
        }

        /// Number of attributes with a value.
        public var count: Int {
            attributeIDs.count
        }

        public subscript(key: AttributeID) -> Double? {
            var low = 0
            var high = attributeIDs.count
            while low < high {
                let mid = (low + high) / 2
                let id = attributeIDs[mid].rawValue
                if id == key.rawValue { return values[mid] }
                if id < key.rawValue { low = mid + 1 } else { high = mid }
            }
            return nil
        }

        public subscript(key: AttributeID, default defaultValue: SDEDefaultMarker) -> Double {
            self[key] ?? Double(sde[key]?.defaultValue ?? 0)
        }

        public func makeIterator() -> Zip2Sequence<[AttributeID], [Double]>.Iterator {
            zip(attributeIDs, values).makeIterator()
        }

        public static func == (lhs: Snapshot, rhs: Snapshot) -> Bool {
            lhs.attributeIDs == rhs.attributeIDs && lhs.values == rhs.values
        }
    }

    /// Copies the entity's calculated attributes. Empty if the entity does not exist.
    public func snapshot() -> Snapshot {
        var pairs: [(AttributeID, Double)] = []
        if session.pointee.entities.contains(entityID) {
            session.pointee.context.attributes.forEach(in: entityID) { pairs.append(($0, $1)) }
        }
        pairs.sort { $0.0.rawValue < $1.0.rawValue }
        return Snapshot(attributeIDs: pairs.map(\.0), values: pairs.map(\.1), sde: session.pointee.sde)
    }
}
