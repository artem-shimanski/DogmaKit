//
//  Fit+Drone.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 16.06.2026.
//

import DogmaModels

extension Fit {
    public struct Drone: ~Copyable, ~Escapable {
        @usableFromInline internal let session: UnsafeMutablePointer<DogmaEngine.Session>
        public let id: DroneID
        @inlinable var entityID: EntityID {id.rawValue}

        @inlinable
        @_lifetime(borrow session)
        init(session: UnsafeMutablePointer<DogmaEngine.Session>, id: DroneID) {
            self.session = session
            self.id = id
        }

        @inlinable
        var entity: Entity {
            get {
                session.pointee.entities[entityID]!
            }
            nonmutating set {
                session.pointee.entities[entityID] = newValue
            }
        }
        @inlinable public var typeID: TypeID { entity.typeID }
        @inlinable public var groupID: GroupID { entity.groupID }
        @inlinable public var categoryID: CategoryID { entity.categoryID }


        @inlinable
        public var squadron: Entity.Drone.Squadron {
            entityID.squadron ?? .none
        }

        /// Maximum squadron/stack size (5 for drones).
        @inlinable
        public var squadronSize: UInt8 {
            entity.kind.drone?.squadronSize ?? 0
        }

        /// Number of drones in the stack / fighters in the squadron.
        @inlinable
        public var count: UInt8 {
            get {
                entity.kind.drone?.count ?? 0
            }
            nonmutating set {
                entity.kind.drone?.count = newValue
            }
        }

        /// Whether the drone or fighter is deployed in space (applies active effects).
        @inlinable
        public var isActive: Bool {
            get {
                entity.kind.drone?.flags.isActive ?? false
            }
            nonmutating set {
                entity.kind.drone?.flags.isActive = newValue
            }
        }

        /// Whether the type has the kamikaze ability (`fighterAbilityKamikaze`).
        @inlinable
        public var hasKamikazeAbility: Bool {
            entity.kind.drone?.flags.hasKamikazeAbility ?? false
        }

        /// Kamikaze mode: the squadron detonates instead of attacking. In this mode
        /// `FitStats.Drone.dps` is zero and all damage is one `kamikazeVolleyDamage` volley.
        ///
        /// Enabling it on a type without the ability is ignored; check `hasKamikazeAbility`.
        @inlinable
        public var isKamikaze: Bool {
            get {
                entity.kind.drone?.flags.isKamikaze ?? false
            }
            nonmutating set {
                guard !newValue || hasKamikazeAbility else { return }
                entity.kind.drone?.flags.isKamikaze = newValue
            }
        }

        /// Drones can always be targeted; mirrors `Fit.Module.isProjectable`.
        @inlinable
        public var isProjectable: Bool { true }

        @inlinable
        public var target: HullID? {
            get {
                guard let target = entity.kind.drone?.target, target != .invalid else {return nil}
                return session.pointee.entities.contains(target) ? HullID(rawValue: target) : nil
            }
            nonmutating set {
                entity.kind.drone?.target = newValue?.rawValue ?? .invalid
            }
        }

        @inlinable
        public var charge: Charge? {
            @_lifetime(borrow self)
            get {
                let chargeID = id.charge
                return session.pointee.entities.contains(chargeID.rawValue) ? Charge(session: session, id: chargeID) : nil
            }
        }

        consuming public func remove() {
            charge?.remove()
            session.pointee.entities.remove(entityID)
        }
    }
}

// MARK: - Mutaplasmids

extension Fit.Drone {

    /// Whether the drone is mutated.
    public var isMutated: Bool {
        entity.mutation != nil
    }

    /// Type ID of the mutaplasmid applied to the drone.
    public var mutaplasmidTypeID: TypeID? {
        session.pointee.mutaplasmidTypeID(of: entityID)
    }

    /// Type ID of the base (unmutated) type.
    public var baseTypeID: TypeID? {
        session.pointee.baseTypeID(of: entityID)
    }

    /// Applies a mutaplasmid to the drone: the type becomes the resulting type, count,
    /// target and `isActive` are kept, rolls reset to base values.
    public func mutate(with mutaplasmidID: TypeID) throws(DogmaError) {
        try session.pointee.remutate(entityID, with: mutaplasmidID)
    }

    /// Mutates the drone and sets rolls at once:
    /// `try drone.mutate(with: .exigentLightDroneFirepowerMutaplasmid, rolls: [(.damageMultiplier, 1.4), (.maxVelocity, 3600)])`.
    ///
    /// Values are absolute and clamped to the mutaplasmid's bounds; unlisted attributes stay
    /// at base values. An attribute outside the mutaplasmid's ranges is an error, checked
    /// before mutating, so the drone is left untouched.
    public func mutate(with mutaplasmidID: TypeID,
                       rolls: some Sequence<(AttributeID, Double)>) throws(DogmaError) {
        try session.pointee.remutate(entityID, with: mutaplasmidID, rolls: rolls)
    }

    /// Removes the mutation: the drone returns to its base type and rolls are deleted.
    public func demutate() throws(DogmaError) {
        try session.pointee.remutate(entityID, with: nil)
    }

    /// Sets an absolute roll value, clamped to the mutaplasmid's bounds.
    public func setRoll(_ value: Double, for attributeID: AttributeID) throws(DogmaError) {
        let sde = session.pointee.sde
        try session.pointee.entities.setRoll(value, for: attributeID, on: entityID, using: sde)
    }

    /// Sets a roll as a multiplier of the base value.
    public func setRoll(multiplier: Double, for attributeID: AttributeID) throws(DogmaError) {
        let sde = session.pointee.sde
        try session.pointee.entities.setRoll(multiplier: multiplier, for: attributeID, on: entityID, using: sde)
    }

    /// Resets all rolls to base values (multiplier 1.0).
    public func resetRolls() {
        let sde = session.pointee.sde
        session.pointee.entities.resetRolls(on: entityID, using: sde)
    }

    /// Iterates the drone's rolls (value, base, bounds, highIsGood).
    public func forEachRoll(_ body: (MutationRoll) -> Void) {
        session.pointee.forEachRoll(of: entityID, body)
    }
}


