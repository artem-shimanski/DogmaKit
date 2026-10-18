//
//  FitStats+Boosters.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 01.08.2026.
//

extension FitStats {
    /// The pilot's boosters, read-only. Mirrors `Fit.Boosters` without the write members.
    public struct Boosters: ~Escapable {
        @usableFromInline internal let session: UnsafePointer<DogmaEngine.Session>
        @usableFromInline internal let pilotID: PilotID

        @inlinable
        @_lifetime(borrow pilot)
        init(pilot: borrowing Pilot) {
            self.session = pilot.session
            self.pilotID = pilot.id
        }

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
    }
}
