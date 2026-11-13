//
//  FittingLimit.swift
//  DogmaKit
//

/// A per-hull limit on how many modules of one group (`maxGroupFitted`) or of one type
/// (`maxTypeFitted`) may be fitted, e.g. one Damage Control, one Rig Synchronizer.
///
/// The limit belongs to the module that carries the attribute, not to its group: in the SDE
/// only some members of a group may have it (2 of 14 Ancillary Shield Boosters). A module is in
/// violation when the hull holds more modules of its group/type than its own limit allows,
/// itself included, so with two Synchronizers fitted both are reported. This is a fitting
/// error only: the engine still evaluates such a fit and does not demote the extra modules.
@frozen
public struct FittingLimit: Sendable, Hashable {
    public enum Scope: Sendable, Hashable {
        /// `maxGroupFitted`: counts modules of this group.
        case group(GroupID)
        /// `maxTypeFitted`: counts modules of this type.
        case type(TypeID)
    }

    public var scope: Scope
    /// The module's limit.
    public var maximum: Int
    /// Modules of the scope fitted to the hull, the module itself included.
    public var fitted: Int

    @inlinable
    public init(scope: Scope, maximum: Int, fitted: Int) {
        self.scope = scope
        self.maximum = maximum
        self.fitted = fitted
    }

    @inlinable
    public var isExceeded: Bool { fitted > maximum }
}

extension DogmaEngine.Session {
    /// Fitting limits carried by a module, with the current counts on its hull. Limits are
    /// read from the calculated attributes; values `<= 0` mean "no limit".
    func fittingLimits(of id: EntityID) -> [FittingLimit] {
        guard let entity = entities[id], entity.kind.module != nil else { return [] }
        var limits: [FittingLimit] = []

        func limit(_ attributeID: AttributeID) -> Int? {
            guard let value = context.attributes[.init(entityID: id, attributeID: attributeID)] else { return nil }
            let maximum = Int(value.rounded())
            return maximum > 0 ? maximum : nil
        }

        func count(where predicate: (Entity) -> Bool) -> Int {
            var count = 0
            for other in entities.modules(on: id.hull) {
                guard let other = entities[other], other.kind.module != nil, predicate(other) else { continue }
                count += 1
            }
            return count
        }

        if let maximum = limit(.maxGroupFitted) {
            let groupID = entity.groupID
            limits.append(FittingLimit(scope: .group(groupID), maximum: maximum,
                                       fitted: count { $0.groupID == groupID }))
        }
        if let maximum = limit(.maxTypeFitted) {
            let typeID = entity.typeID
            limits.append(FittingLimit(scope: .type(typeID), maximum: maximum,
                                       fitted: count { $0.typeID == typeID }))
        }
        return limits
    }
}
