//
//  Mutation.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 28.07.2026.
//

import DogmaModels
import FlatBin

/// A mutation (abyssal / dynamic item): an item produced by applying a mutaplasmid to a base type.
///
/// The resulting type has almost no attributes of its own in the SDE, so base values are
/// assembled in three layers (see `ContextBuilder.reloadBaseAttributes`):
/// 1. attributes of the base type,
/// 2. the resulting type's own attributes override them,
/// 3. rolls override everything.
///
/// Effects, group, category and required skills come from the resulting type.
/// Mutations do not take part in the fixed-point iteration.
public struct Mutation: BitwiseCopyable, Sendable {
    public var mutaplasmid: FlatReference<DogmaSDE.Mutaplasmid>
    public var baseType: FlatReference<DogmaSDE.TypeInfo>

    public init(mutaplasmid: FlatReference<DogmaSDE.Mutaplasmid>, baseType: FlatReference<DogmaSDE.TypeInfo>) {
        self.mutaplasmid = mutaplasmid
        self.baseType = baseType
    }

    /// One roll: a replaced base attribute value. The value is absolute, as in the game and
    /// ESI; the multiplier is derived.
    public struct Roll: BitwiseCopyable, Sendable {
        public var attributeID: AttributeID
        public var value: Double

        public init(attributeID: AttributeID, value: Double) {
            self.attributeID = attributeID
            self.value = value
        }
    }
}

extension Mutation {
    /// Clamps a roll to the mutaplasmid's bounds. Bounds are multipliers of the base value;
    /// with a zero base the roll is always 0; min/max are taken of the products because a
    /// negative base swaps the bounds.
    @inlinable
    public static func clamped(_ value: Double, base: Double, min minMultiplier: Float, max maxMultiplier: Float) -> Double {
        guard base != 0 else { return 0 }
        let lo = Double(minMultiplier) * base
        let hi = Double(maxMultiplier) * base
        return Swift.min(Swift.max(value, Swift.min(lo, hi)), Swift.max(lo, hi))
    }
}

/// A roll in a form convenient for a mutation editor UI.
public struct MutationRoll: BitwiseCopyable, Sendable {
    public var attributeID: AttributeID
    /// Current absolute value of the attribute on the mutated item.
    public var value: Double
    /// Base type value of the attribute; the reference for multipliers.
    public var baseValue: Double
    /// Mutaplasmid `min` multiplied by the base value.
    public var minValue: Double
    /// Mutaplasmid `max` multiplied by the base value.
    public var maxValue: Double
    /// Mutaplasmid `highIsGood` if it overrides it, otherwise from `AttributeInfo`.
    public var highIsGood: Bool

    @inlinable
    public var multiplier: Double {
        baseValue == 0 ? 1 : value / baseValue
    }

    /// Roll bounds in ascending order (with a negative base `minValue` is greater than `maxValue`).
    @inlinable
    public var range: ClosedRange<Double> {
        Swift.min(minValue, maxValue)...Swift.max(minValue, maxValue)
    }
}

/// Attribute value of a type, taking the mutation into account: the resulting type wins,
/// missing values come from the base type. Merged per attribute, since some resulting types
/// have `chargeSize` but no `chargeGroup`. Used outside the calculation context.
func typeAttribute(_ attributeID: AttributeID,
                   of type: DogmaSDE.TypeInfo.View,
                   base: DogmaSDE.TypeInfo.View?) -> Float? {
    if let value = type.attributes[attributeID]?.load() { return value }
    if let base, let value = base.attributes[attributeID]?.load() { return value }
    return nil
}

extension EntityStore {

    /// Resets rolls to the base values (multiplier 1.0), i.e. an unrolled item.
    mutating func resetRolls(on id: EntityID, using sde: SDE) {
        guard let entity = self[id], let mutation = entity.mutation else {
            mutations[id] = nil
            return
        }
        let mutaplasmid = sde[mutation.mutaplasmid]
        let base = sde[mutation.baseType]
        var rolls: [Mutation.Roll] = []
        rolls.reserveCapacity(mutaplasmid.ranges.count)
        mutaplasmid.ranges.forEach { rangeView in
            let range = rangeView.load()
            rolls.append(Mutation.Roll(attributeID: range.id,
                                       value: Double(base.attributes[range.id]?.load() ?? 0)))
        }
        setRolls(rolls, for: id)
    }

    /// Sets an absolute roll value, clamped to the mutaplasmid's bounds.
    mutating func setRoll(_ value: Double,
                          for attributeID: AttributeID,
                          on id: EntityID,
                          using sde: SDE) throws(DogmaError) {
        try updateRoll(for: attributeID, on: id, using: sde) { base, range in
            Mutation.clamped(value, base: base, min: range.min, max: range.max)
        }
    }

    /// Sets a roll as a multiplier of the base value (0.6…1.4, etc.).
    mutating func setRoll(multiplier: Double,
                          for attributeID: AttributeID,
                          on id: EntityID,
                          using sde: SDE) throws(DogmaError) {
        try updateRoll(for: attributeID, on: id, using: sde) { base, range in
            Mutation.clamped(multiplier * base, base: base, min: range.min, max: range.max)
        }
    }

    private mutating func updateRoll(for attributeID: AttributeID,
                                     on id: EntityID,
                                     using sde: SDE,
                                     _ transform: (Double, DogmaSDE.Mutaplasmid.Range) -> Double) throws(DogmaError) {
        guard let entity = self[id], let mutation = entity.mutation else {
            throw DogmaError.notMutated(id)
        }
        let mutaplasmid = sde[mutation.mutaplasmid]

        // A mutaplasmid has 2…10 ranges; linear search is fine.
        var found: DogmaSDE.Mutaplasmid.Range? = nil
        mutaplasmid.ranges.forEach { rangeView in
            let range = rangeView.load()
            if range.id == attributeID { found = range }
        }
        guard let range = found else {
            throw DogmaError.attributeNotMutable(attributeID, by: mutaplasmid.id.load())
        }

        let base = Double(sde[mutation.baseType].attributes[attributeID]?.load() ?? 0)
        let value = transform(base, range)

        var rolls = mutations[id] ?? []
        if let index = rolls.firstIndex(where: { $0.attributeID == attributeID }) {
            rolls[index].value = value
        } else {
            rolls.append(Mutation.Roll(attributeID: attributeID, value: value))
            rolls.sort { $0.attributeID.rawValue < $1.attributeID.rawValue }
        }
        mutations[id] = rolls
    }
}

extension DogmaEngine.Session {

    /// Applies a mutaplasmid to an existing entity, or removes the mutation (`nil`),
    /// preserving user state. The module slot and drone squadron are encoded in the
    /// `EntityID`, so a type change that alters them is rejected.
    mutating func remutate(_ id: EntityID, with mutaplasmidID: TypeID?) throws(DogmaError) {
        let sde = self.sde
        guard var entity = entities[id] else { return }

        // Base type: the original one for an already mutated entity, so re-applying
        // a mutaplasmid does not mutate the mutation.
        let baseTypeID: TypeID
        if let mutation = entity.mutation {
            baseTypeID = sde[mutation.baseType].id.load()
        } else {
            baseTypeID = entity.typeID
        }
        guard let base = sde[baseTypeID] else { throw DogmaError.typeNotFound(baseTypeID) }

        var mutation: Mutation? = nil
        var typeID = baseTypeID

        if let mutaplasmidID {
            guard let mutaplasmid = sde.mutaplasmid(mutaplasmidID) else {
                throw DogmaError.mutaplasmidNotFound(mutaplasmidID)
            }
            guard mutaplasmid.applicableTypes.contains(baseTypeID) else {
                throw DogmaError.mutaplasmidNotApplicable(mutaplasmidID, to: baseTypeID)
            }
            typeID = mutaplasmid.resultingTypeID.load()
            mutation = Mutation(mutaplasmid: mutaplasmid.reference, baseType: base.reference)
        }

        guard let info = sde[typeID] else { throw DogmaError.typeNotFound(typeID) }

        // When removing a mutation `info == base`, so passing `base` is always safe.
        switch entity.kind {
        case let .module(module):
            var updated = Entity.Module(info, base: base)
            guard updated.slot == module.slot else {
                throw DogmaError.cantFit(typeID, to: entity.typeID)
            }
            updated.state = module.state
            updated.target = module.target
            updated.socket = module.socket
            entity.kind = .module(updated)

        case let .drone(drone):
            var updated = Entity.Drone(info, base: base)
            guard updated.squadron == drone.squadron else {
                throw DogmaError.cantFit(typeID, to: entity.typeID)
            }
            updated.target = drone.target
            updated.count = Swift.min(drone.count, updated.squadronSize)
            updated.flags.isActive = drone.flags.isActive
            updated.flags.isKamikaze = drone.flags.isKamikaze && updated.flags.hasKamikazeAbility
            entity.kind = .drone(updated)

        default:
            throw DogmaError.invalidCategory(entity.categoryID, expected: [.module, .subsystem, .drone, .fighter])
        }

        entity.typeID = typeID
        entity.groupID = info.groupID.load()
        entity.categoryID = info.categoryID.load()
        entity.info = info.reference
        entity.mutation = mutation
        entities[id] = entity

        if mutation != nil {
            entities.resetRolls(on: id, using: sde)
        } else {
            entities.setRolls([], for: id)
        }
    }

    /// Mutates with a given set of rolls in one call. Attributes are validated against
    /// the mutaplasmid's ranges before mutating, so on error the entity is left untouched.
    /// Values are clamped, as in `setRoll`.
    mutating func remutate(_ id: EntityID,
                           with mutaplasmidID: TypeID,
                           rolls: some Sequence<(AttributeID, Double)>) throws(DogmaError) {
        let sde = self.sde
        guard let mutaplasmid = sde.mutaplasmid(mutaplasmidID) else {
            throw DogmaError.mutaplasmidNotFound(mutaplasmidID)
        }
        for (attributeID, _) in rolls {
            var isMutable = false
            mutaplasmid.ranges.forEach { rangeView in
                if rangeView.load().id == attributeID { isMutable = true }
            }
            guard isMutable else {
                throw DogmaError.attributeNotMutable(attributeID, by: mutaplasmidID)
            }
        }

        try remutate(id, with: mutaplasmidID)
        for (attributeID, value) in rolls {
            try entities.setRoll(value, for: attributeID, on: id, using: sde)
        }
    }

    /// Type ID of the mutaplasmid, if the entity is mutated.
    func mutaplasmidTypeID(of id: EntityID) -> TypeID? {
        guard let mutation = entities[id]?.mutation else { return nil }
        return sde[mutation.mutaplasmid].id.load()
    }

    /// Type ID of the base (unmutated) type, if the entity is mutated.
    func baseTypeID(of id: EntityID) -> TypeID? {
        guard let mutation = entities[id]?.mutation else { return nil }
        return sde[mutation.baseType].id.load()
    }

    /// Iterates the entity's rolls in `attributeID` order, covering every mutaplasmid range;
    /// attributes without a roll report the base value (multiplier 1.0).
    func forEachRoll(of id: EntityID, _ body: (MutationRoll) -> Void) {
        let sde = self.sde
        guard let entity = entities[id], let mutation = entity.mutation else { return }
        let mutaplasmid = sde[mutation.mutaplasmid]
        let base = sde[mutation.baseType]
        let rolls = entities.rolls(for: id) ?? []

        mutaplasmid.ranges.forEach { rangeView in
            let range = rangeView.load()
            let baseValue = Double(base.attributes[range.id]?.load() ?? 0)
            let value = rolls.first { $0.attributeID == range.id }?.value ?? baseValue

            var highIsGood = range.highIsGood.asBool
            if highIsGood == nil {
                highIsGood = sde[range.id]?.options.load().contains(.highIsGood)
            }

            body(MutationRoll(attributeID: range.id,
                              value: value,
                              baseValue: baseValue,
                              minValue: Double(range.min) * baseValue,
                              maxValue: Double(range.max) * baseValue,
                              highIsGood: highIsGood ?? false))
        }
    }
}
