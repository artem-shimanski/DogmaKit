//
//  Fit+Module.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 01.07.2026.
//

import BitField

extension Fit {
    
    public struct Module: ~Copyable, ~Escapable {
        @usableFromInline internal let session: UnsafeMutablePointer<DogmaEngine.Session>
        public let id: ModuleID
        @inlinable var entityID: EntityID {id.rawValue}
        
        @inlinable
        @_lifetime(borrow session)
        init(session: UnsafeMutablePointer<DogmaEngine.Session>, id: ModuleID) {
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


        /// The highest state the module supports.
        @inlinable
        public var maxAllowedState: Entity.Module.State {
            entity.kind.module?.flags.maxAllowedState ?? .offline
        }

        /// Whether the module can have a target: an effect of category `.target` with
        /// modifiers on the `.target` domain (remote repair, warp disruptor, …). Weapons cannot.
        public var isProjectable: Bool {
            let sde = session.pointee.sde
            return Entity.Module.isProjectable(sde[entity.info])
        }

        @inlinable
        public var state: Entity.Module.State {
            get {
                entity.kind.module?.state ?? .offline
            }
            nonmutating set {
                entity.kind.module?.state = newValue
            }
        }
        
        /// Position of the module in its rack. Defaults to the first free index at `add` time.
        ///
        /// Assigning swaps modules: if the target socket is taken, the module occupying it
        /// moves to the vacated one. The value is not validated against the hull's slot count;
        /// modules with a socket outside the rack are ignored when reading.
        @inlinable
        public var socket: Int {
            get {
                Int(entity.kind.module?.socket ?? 0)
            }
            nonmutating set {
                guard var module = entity.kind.module else { return }
                let target = UInt8(clamping: newValue)
                let previous = module.socket
                guard target != previous else { return }

                let allocator = EntityID.module(in: module.slot, on: id.hull.rawValue)
                for other in session.pointee.entities.ids(in: allocator) where other != entityID {
                    guard session.pointee.entities[other]?.kind.module?.socket == target else { continue }
                    session.pointee.entities[other]?.kind.module?.socket = previous
                    break
                }

                module.socket = target
                entity.kind = .module(module)
            }
        }

        @inlinable
        public var target: HullID? {
            get {
                guard let target = entity.kind.module?.target, target != .invalid else {return nil}
                return session.pointee.entities.contains(target) ? HullID(rawValue: target) : nil
            }
            nonmutating set {
                entity.kind.module?.target = newValue?.rawValue ?? .invalid
            }
        }
        
        consuming public func remove() {
            charge?.remove()
            session.pointee.entities.remove(entityID)
        }
        
        @inlinable
        public var charge: Charge? {
            @_lifetime(borrow self)
            get {
                let chargeID = id.charge
                return session.pointee.entities.contains(chargeID.rawValue) ? Charge(session: session, id: chargeID) : nil
            }
        }
        
        public func setCharge(_ typeID: TypeID) throws(DogmaError) {
            let sde = session.pointee.sde
            guard let chargeInfo = sde[typeID] else { throw DogmaError.typeNotFound(typeID)}
            let entity = self.entity
            let moduleInfo = sde[entity.info]

            // Abyssal modules keep charge requirements and `capacity` on the base type.
            var canLoad = false
            if let requirements = moduleInfo.chargeRequirements {
                canLoad = requirements.canLoad(with: chargeInfo)
            }
            else if let mutation = entity.mutation,
                    let requirements = sde[mutation.baseType].chargeRequirements {
                canLoad = requirements.canLoad(with: chargeInfo)
            }
            guard canLoad else { throw DogmaError.cantFit(typeID, to: moduleInfo.id.load()) }

            var capacity = moduleInfo.attributes[.capacity]?.load()
            if capacity == nil, let mutation = entity.mutation {
                capacity = sde[mutation.baseType].attributes[.capacity]?.load()
            }
            if let capacity, let volume = chargeInfo.attributes[.volume]?.load(), capacity < volume {
                throw DogmaError.cantFit(typeID, to: moduleInfo.id.load())
            }

            let chargeID = id.charge.rawValue
            let charge = Entity.Charge(chargeInfo)
            let chargeEntity = Entity(id: chargeID, typeID: typeID, groupID: chargeInfo.groupID.load(), categoryID: chargeInfo.categoryID.load(), info: chargeInfo.reference, kind: .charge(charge))
            session.pointee.entities[chargeID] = chargeEntity
        }
    }
}

// MARK: - Mutaplasmids

extension Fit.Module {

    /// Whether the module is mutated (abyssal).
    public var isMutated: Bool {
        entity.mutation != nil
    }

    /// Type ID of the mutaplasmid applied to the module.
    public var mutaplasmidTypeID: TypeID? {
        session.pointee.mutaplasmidTypeID(of: entityID)
    }

    /// Type ID of the base (unmutated) type.
    public var baseTypeID: TypeID? {
        session.pointee.baseTypeID(of: entityID)
    }

    /// Applies a mutaplasmid to the fitted module: the type becomes the resulting type,
    /// state, target and charge are kept, rolls reset to base values. Calling it again
    /// mutates the original base type, not the current abyssal one.
    public func mutate(with mutaplasmidID: TypeID) throws(DogmaError) {
        try session.pointee.remutate(entityID, with: mutaplasmidID)
    }

    /// Mutates the module and sets rolls at once:
    /// `try module.mutate(with: .gravidWarpScramblerMutaplasmid, rolls: [(.cpu, 45), (.warpScrambleRange, 12_500)])`.
    ///
    /// Values are absolute (as in the game and ESI) and clamped to the mutaplasmid's bounds;
    /// unlisted attributes stay at base values. An attribute outside the mutaplasmid's ranges
    /// is an error, checked before mutating, so the module is left untouched.
    public func mutate(with mutaplasmidID: TypeID,
                       rolls: some Sequence<(AttributeID, Double)>) throws(DogmaError) {
        try session.pointee.remutate(entityID, with: mutaplasmidID, rolls: rolls)
    }

    /// Removes the mutation: the module returns to its base type and rolls are deleted.
    public func demutate() throws(DogmaError) {
        try session.pointee.remutate(entityID, with: nil)
    }

    /// Sets an absolute roll value (as in the game and ESI), clamped to the mutaplasmid's
    /// bounds. An attribute outside its ranges is an error.
    public func setRoll(_ value: Double, for attributeID: AttributeID) throws(DogmaError) {
        let sde = session.pointee.sde
        try session.pointee.entities.setRoll(value, for: attributeID, on: entityID, using: sde)
    }

    /// Sets a roll as a multiplier of the base value (0.6…1.4, etc.).
    public func setRoll(multiplier: Double, for attributeID: AttributeID) throws(DogmaError) {
        let sde = session.pointee.sde
        try session.pointee.entities.setRoll(multiplier: multiplier, for: attributeID, on: entityID, using: sde)
    }

    /// Resets all rolls to base values (multiplier 1.0).
    public func resetRolls() {
        let sde = session.pointee.sde
        session.pointee.entities.resetRolls(on: entityID, using: sde)
    }

    /// Iterates the module's rolls (value, base, bounds, highIsGood).
    public func forEachRoll(_ body: (MutationRoll) -> Void) {
        session.pointee.forEachRoll(of: entityID, body)
    }
}


