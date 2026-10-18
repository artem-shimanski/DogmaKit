//
//  FitStats+Pilots.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 01.08.2026.
//

extension FitStats {
    /// The fit's pilots, read-only. Mirrors `Fit.Pilots` without the write members.
    public struct Pilots: ~Escapable {
        @usableFromInline internal let session: UnsafePointer<DogmaEngine.Session>

        @inlinable
        @_lifetime(borrow stats)
        init(stats: borrowing FitStats) {
            self.session = stats.session
        }

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
    }
}
