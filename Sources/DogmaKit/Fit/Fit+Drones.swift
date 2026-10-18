//
//  Fit+Drones.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 01.08.2026.
//

extension Fit {
    /// The hull's drones and fighters, writable. Members follow `Fit.Modules`.
    public struct Drones: ~Copyable, ~Escapable {
        @usableFromInline internal let session: UnsafeMutablePointer<DogmaEngine.Session>
        @usableFromInline internal let hullID: HullID

        @inlinable
        @_lifetime(borrow hull)
        init(hull: borrowing Hull) {
            self.session = hull.session
            self.hullID = hull.id
        }

        // MARK: - Reading

        @inlinable
        public var allIDs: some Sequence<DroneID> {
            session.pointee.entities.drones(on: hullID.rawValue).as(DroneID.self)
        }

        @inlinable
        public func ids(in squadron: Entity.Drone.Squadron) -> some Sequence<DroneID> {
            session.pointee.entities.ids(in: .drone(in: squadron, on: hullID.rawValue)).as(DroneID.self)
        }

        @inlinable
        public subscript(id: DroneID) -> Drone {
            @_lifetime(copy self) get {
                _overrideLifetime(Drone(session: session, id: id), copying: self)
            }
        }

        public func forEach(_ body: (borrowing Drone) -> Void) {
            for id in allIDs {
                body(Drone(session: session, id: id))
            }
        }

        public func forEach(in squadron: Entity.Drone.Squadron, _ body: (borrowing Drone) -> Void) {
            for id in ids(in: squadron) {
                body(Drone(session: session, id: id))
            }
        }

        public var count: Int {
            allIDs.count()
        }

        public func count(in squadron: Entity.Drone.Squadron) -> Int {
            ids(in: squadron).count()
        }

        // MARK: - Writing

        /// Adds a drone or fighter. `count` defaults to the type's value
        /// (`fighterSquadronMaxSize` for fighters, 1 for drones).
        @discardableResult
        @_lifetime(copy self)
        public func add(_ typeID: TypeID, count: UInt8? = nil) throws(DogmaError) -> Drone {
            let sde = session.pointee.sde
            guard let info = sde[typeID] else { throw DogmaError.typeNotFound(typeID)}
            let droneID = try append(info, base: nil, mutation: nil, count: count)
            let drone = Drone(session: session, id: droneID)
            return _overrideLifetime(drone, copying: self)
        }

        /// Adds a mutated drone. `typeID` is the base type (Acolyte II, etc.); the resulting
        /// type is derived from the mutaplasmid. Fighters cannot be mutated.
        @discardableResult
        @_lifetime(copy self)
        public func add(_ typeID: TypeID, mutaplasmid mutaplasmidID: TypeID, count: UInt8? = nil) throws(DogmaError) -> Drone {
            let sde = session.pointee.sde
            guard let mutaplasmid = sde.mutaplasmid(mutaplasmidID) else {
                throw DogmaError.mutaplasmidNotFound(mutaplasmidID)
            }
            guard mutaplasmid.applicableTypes.contains(typeID) else {
                throw DogmaError.mutaplasmidNotApplicable(mutaplasmidID, to: typeID)
            }
            guard let base = sde[typeID] else { throw DogmaError.typeNotFound(typeID) }

            let resultingTypeID = mutaplasmid.resultingTypeID.load()
            guard let info = sde[resultingTypeID] else { throw DogmaError.typeNotFound(resultingTypeID) }

            let mutation = Mutation(mutaplasmid: mutaplasmid.reference, baseType: base.reference)
            let droneID = try append(info, base: base, mutation: mutation, count: count)
            session.pointee.entities.resetRolls(on: droneID.rawValue, using: sde)
            let drone = Drone(session: session, id: droneID)
            return _overrideLifetime(drone, copying: self)
        }

        /// Shared body of both `add` methods.
        private func append(_ info: DogmaSDE.TypeInfo.View,
                            base: DogmaSDE.TypeInfo.View?,
                            mutation: Mutation?,
                            count: UInt8?) throws(DogmaError) -> DroneID {
            let sde = session.pointee.sde
            let typeID = info.id.load()
            let categoryID = info.categoryID.load()

            guard categoryID == .fighter || categoryID == .drone else {
                throw DogmaError.invalidCategory(categoryID, expected: [.fighter, .drone])
            }

            var drone = Entity.Drone(info, base: base)
            if let count { drone.count = count }
            let droneID = try session.pointee.entities.append(in: .drone(in: drone.squadron, on: hullID.rawValue)) { id in
                Entity(id: id,
                       typeID: typeID,
                       groupID: info.groupID.load(),
                       categoryID: categoryID,
                       info: info.reference,
                       mutation: mutation,
                       kind: .drone(drone))
            }

            // Built-in ammo: missile drones (`entityMissileTypeID`) and bomber fighters
            // (`fighterAbilityLaunchBombType`) get their charge loaded automatically.
            if let chargeTypeIDValue = typeAttribute(.entityMissileTypeID, of: info, base: base)
                ?? typeAttribute(.fighterAbilityLaunchBombType, of: info, base: base),
               chargeTypeIDValue > 0 {
                let chargeTypeID = TypeID(rawValue: UInt32(chargeTypeIDValue))
                if let chargeInfo = sde[chargeTypeID] {
                    let chargeID = EntityID.charge(in: droneID)
                    let charge = Entity.Charge(chargeInfo)
                    session.pointee.entities[chargeID] = Entity(id: chargeID,
                                                                typeID: chargeTypeID,
                                                                groupID: chargeInfo.groupID.load(),
                                                                categoryID: chargeInfo.categoryID.load(),
                                                                info: chargeInfo.reference,
                                                                kind: .charge(charge))
                }
            }
            return DroneID(rawValue: droneID)
        }
    }
}
