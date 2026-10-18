//
//  Fit+Pilots.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 01.08.2026.
//

extension Fit {
    /// The fit's pilots, writable. Members follow `Fit.Modules`; there is no domain key,
    /// so only `allIDs` / `subscript(_:)`.
    public struct Pilots: ~Copyable, ~Escapable {
        @usableFromInline internal let session: UnsafeMutablePointer<DogmaEngine.Session>

        @inlinable
        @_lifetime(borrow fit)
        init(fit: borrowing Fit) {
            self.session = fit.session
        }

        /// Maximum number of pilots. `EntityID.pilotID` is 3 bits and 0 is reserved for the
        /// environment, leaving 1...7; the same index is used in `UInt8` masks (`1 << pilotID`).
        public static var maxCount: Int { Int(EntityID.$pilotID.maxValue) }

        // MARK: - Reading

        @inlinable
        public var allIDs: some Sequence<PilotID> {
            session.pointee.entities.ids(in: .pilot()).as(PilotID.self)
        }

        @inlinable
        public subscript(id: PilotID) -> Pilot {
            @_lifetime(copy self) get {
                _overrideLifetime(Pilot(session: session, id: id), copying: self)
            }
        }

        public func forEach(_ body: (borrowing Pilot) -> Void) {
            for id in allIDs {
                body(Pilot(session: session, id: id))
            }
        }

        public var count: Int {
            allIDs.count()
        }

        // MARK: - Writing

        /// Creates a pilot: the pilot entity, all SDE skills at `skillLevel`, and a capsule
        /// as the starting hull.
        @discardableResult
        @_lifetime(copy self)
        public func add(skillLevel: UInt8) throws(DogmaError) -> Pilot {
            // Check before any allocation, so a pilot without skills is never left in the store.
            guard count < Self.maxCount else { throw DogmaError.pilotLimitExceeded }
            let sde = session.pointee.sde
            let info = sde[TypeID.characterType]!
            let pilotID = try session.pointee.entities.append(in: .gang) { id in
                return Entity(id: id,
                              typeID: .characterType,
                              groupID: info.groupID.load(),
                              categoryID: info.categoryID.load(),
                              info: info.reference,
                              kind: .pilot)
            }
            let count = sde.skills.count
            var skillIDMap: [TypeID: UInt16]? = session.pointee.skillIDMap == nil ? [:] : nil
            skillIDMap?.reserveCapacity(count)

            try sde.skills.forEach { (typeID) throws(DogmaError) in
                let typeID = typeID.load()
                try session.pointee.entities.append(in: .skill(for: pilotID)) { id in
                    if skillIDMap != nil {
                        skillIDMap?[typeID] = id.rawID
                    }
                    let info = sde[typeID]!
                    return Entity(id: id,
                                  typeID: typeID,
                                  groupID: info.groupID.load(),
                                  categoryID: info.categoryID.load(),
                                  info: info.reference,
                                  kind: .skill(level: skillLevel))
                }
            }
            if skillIDMap != nil {
                session.pointee.skillIDMap = skillIDMap
            }

            let hullID = EntityID.hull(for: pilotID)
            let capsule = sde[TypeID.capsule]!
            session.pointee.entities[hullID] = Entity(id: hullID,
                                                     typeID: .capsule,
                                                     groupID: capsule.groupID.load(),
                                                     categoryID: capsule.categoryID.load(),
                                                     info: capsule.reference,
                                                     kind: .ship)
            let pilot = Pilot(session: session, id: PilotID(rawValue: pilotID))
            return _overrideLifetime(pilot, copying: self)
        }
    }
}
