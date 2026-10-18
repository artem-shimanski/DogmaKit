//
//  FitStats+Implants.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 01.08.2026.
//

extension FitStats {
    /// The pilot's implants, read-only. Mirrors `Fit.Implants` without the write members.
    public struct Implants: ~Escapable {
        @usableFromInline internal let session: UnsafePointer<DogmaEngine.Session>
        @usableFromInline internal let pilotID: PilotID

        @inlinable
        @_lifetime(borrow pilot)
        init(pilot: borrowing Pilot) {
            self.session = pilot.session
            self.pilotID = pilot.id
        }

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
    }
}
