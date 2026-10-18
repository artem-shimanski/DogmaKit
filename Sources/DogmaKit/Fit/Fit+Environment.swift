//
//  Fit+Environment.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 02.08.2026.
//

extension Fit {
    /// The simulation environment, writable. Environment effects (wormhole and incursion
    /// beacons, abyssal weather, Triglavian storms) apply to every ship in the session:
    /// `Domain.resolve` expands their `shipID`/`charID` domains to all hulls and pilots.
    /// Owned by `Fit`, not a pilot. Members follow `Fit.Modules`.
    public struct Environment: ~Copyable, ~Escapable {
        @usableFromInline internal let session: UnsafeMutablePointer<DogmaEngine.Session>

        @inlinable
        @_lifetime(borrow fit)
        init(fit: borrowing Fit) {
            self.session = fit.session
        }

        // MARK: - Reading

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

        // MARK: - Writing

        /// Adds an environment effect. The type must be in the Celestial category
        /// (Effect Beacon, Abyssal Hazards, MassiveEnvironments, Triglavian Support Pylons).
        /// Duplicates are allowed: two identical beacons are two sources of the same bonus.
        @discardableResult
        @_lifetime(copy self)
        public func add(_ typeID: TypeID) throws(DogmaError) -> EnvironmentEffect {
            let sde = session.pointee.sde
            guard let info = sde[typeID] else { throw DogmaError.typeNotFound(typeID) }
            let categoryID = info.categoryID.load()
            guard categoryID == .celestial else {
                throw DogmaError.invalidCategory(categoryID, expected: [.celestial])
            }

            let id = try session.pointee.entities.append(in: .environment()) { id in
                Entity(id: id,
                       typeID: info.id.load(),
                       groupID: info.groupID.load(),
                       categoryID: categoryID,
                       info: info.reference,
                       kind: .environment)
            }
            let effect = EnvironmentEffect(session: session, id: EnvironmentID(rawValue: id))
            return _overrideLifetime(effect, copying: self)
        }

        /// Removes all environment effects.
        public func removeAll() {
            for id in Array(allIDs) {
                session.pointee.entities.remove(id.rawValue)
            }
        }
    }
}
