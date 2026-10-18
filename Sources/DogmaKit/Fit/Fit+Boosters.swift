//
//  Fit+Boosters.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 01.08.2026.
//

extension Fit {
    /// The pilot's boosters, writable. Members follow `Fit.Implants`; the domain key is the
    /// `boosterness` slot.
    public struct Boosters: ~Copyable, ~Escapable {
        @usableFromInline internal let session: UnsafeMutablePointer<DogmaEngine.Session>
        @usableFromInline internal let pilotID: PilotID

        @inlinable
        @_lifetime(borrow pilot)
        init(pilot: borrowing Pilot) {
            self.session = pilot.session
            self.pilotID = pilot.id
        }

        // MARK: - Reading

        @inlinable
        public var allIDs: some Sequence<BoosterID> {
            session.pointee.entities.ids(in: .booster(for: pilotID.rawValue)).as(BoosterID.self)
        }

        @inlinable
        public subscript(id: BoosterID) -> Booster {
            @_lifetime(copy self) get {
                _overrideLifetime(Booster(session: session, id: id), copying: self)
            }
        }

        @inlinable
        public subscript(slot slot: UInt16) -> Booster? {
            @_lifetime(copy self) get {
                for id in allIDs {
                    let booster = Booster(session: session, id: id)
                    if booster.slot == slot {
                        return _overrideLifetime(booster, copying: self)
                    }
                }
                return nil
            }
        }

        public func forEach(_ body: (borrowing Booster) -> Void) {
            for id in allIDs {
                body(Booster(session: session, id: id))
            }
        }

        public var count: Int {
            allIDs.count()
        }

        // MARK: - Writing

        @discardableResult
        @_lifetime(copy self)
        public func add(_ typeID: TypeID) throws(DogmaError) -> Booster {
            let sde = session.pointee.sde
            guard let info = sde[typeID] else { throw DogmaError.typeNotFound(typeID)}
            let typeID = info.id.load()
            let groupID = info.groupID.load()
            let categoryID = info.categoryID.load()

            guard categoryID == .implant else { throw DogmaError.invalidCategory(categoryID, expected: [.implant]) }
            guard let slot = (info.attributes[.boosterness]?.load()).flatMap({UInt16(exactly: $0)}) else {
                throw DogmaError.attributeNotFound(.boosterness)
            }

            if let existing = self[slot: slot] {
                throw DogmaError.boosterSlotOccupied(typeID, by: existing.typeID)
            }

            let boosterID = try session.pointee.entities.append(in: .booster(for: pilotID.rawValue)) { id in
                Entity(id: id, typeID: typeID, groupID: groupID, categoryID: categoryID, info: info.reference, kind: .booster(slot: slot))
            }
            let booster = Booster(session: session, id: BoosterID(rawValue: boosterID))
            return _overrideLifetime(booster, copying: self)
        }
    }
}
