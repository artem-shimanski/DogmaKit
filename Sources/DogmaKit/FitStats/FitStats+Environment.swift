//
//  FitStats+Environment.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 02.08.2026.
//

extension FitStats {
    /// The simulation environment, read-only. Mirrors `Fit.Environment` without the write members.
    public struct Environment: ~Escapable {
        @usableFromInline internal let session: UnsafePointer<DogmaEngine.Session>

        @inlinable
        @_lifetime(borrow stats)
        init(stats: borrowing FitStats) {
            self.session = stats.session
        }

        @inlinable
        public var allIDs: some Sequence<EnvironmentID> {
            session.pointee.entities.ids(in: .environment()).as(EnvironmentID.self)
        }

        @inlinable
        public subscript(id: EnvironmentID) -> EnvironmentEffect {
            @_lifetime(copy self) get {
                _overrideLifetime(EnvironmentEffect(session: session, id: id), copying: self)
            }
        }

        public func forEach(_ body: (borrowing EnvironmentEffect) -> Void) {
            for id in allIDs {
                body(EnvironmentEffect(session: session, id: id))
            }
        }

        public var count: Int {
            allIDs.count()
        }
    }
}
