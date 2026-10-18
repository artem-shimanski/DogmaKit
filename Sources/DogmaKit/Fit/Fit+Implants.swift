//
//  Fit+Implants.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 01.08.2026.
//

extension Fit {
    /// The pilot's implants, writable. Members follow `Fit.Modules`; the unique domain key is
    /// the `implantness` slot (`subscript(slot:)`).
    public struct Implants: ~Copyable, ~Escapable {
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
        public var allIDs: some Sequence<ImplantID> {
            session.pointee.entities.ids(in: .implant(for: pilotID.rawValue)).as(ImplantID.self)
        }

        @inlinable
        public subscript(id: ImplantID) -> Implant {
            @_lifetime(copy self) get {
                _overrideLifetime(Implant(session: session, id: id), copying: self)
            }
        }

        @inlinable
        public subscript(slot slot: UInt16) -> Implant? {
            @_lifetime(copy self) get {
                for id in allIDs {
                    let implant = Implant(session: session, id: id)
                    if implant.slot == slot {
                        return _overrideLifetime(implant, copying: self)
                    }
                }
                return nil
            }
        }

        public func forEach(_ body: (borrowing Implant) -> Void) {
            for id in allIDs {
                body(Implant(session: session, id: id))
            }
        }

        public var count: Int {
            allIDs.count()
        }

        // MARK: - Writing

        @discardableResult
        @_lifetime(copy self)
        public func add(_ typeID: TypeID) throws(DogmaError) -> Implant {
            let sde = session.pointee.sde
            guard let info = sde[typeID] else { throw DogmaError.typeNotFound(typeID)}
            let typeID = info.id.load()
            let groupID = info.groupID.load()
            let categoryID = info.categoryID.load()

            guard categoryID == .implant else { throw DogmaError.invalidCategory(categoryID, expected: [.implant]) }
            guard let slot = (info.attributes[.implantness]?.load()).flatMap({UInt16(exactly: $0)}) else {
                throw DogmaError.attributeNotFound(.implantness)
            }

            if let existing = self[slot: slot] {
                throw DogmaError.implantSlotOccupied(typeID, by: existing.typeID)
            }

            let implantID = try session.pointee.entities.append(in: .implant(for: pilotID.rawValue)) { id in
                Entity(id: id, typeID: typeID, groupID: groupID, categoryID: categoryID, info: info.reference, kind: .implant(slot: slot))
            }
            let implant = Implant(session: session, id: ImplantID(rawValue: implantID))
            return _overrideLifetime(implant, copying: self)
        }
    }
}
