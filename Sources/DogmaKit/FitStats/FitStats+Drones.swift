//
//  FitStats+Drones.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 01.08.2026.
//

extension FitStats {
    /// The hull's drones and fighters, read-only. Mirrors `Fit.Drones` without the write members.
    public struct Drones: ~Escapable {
        @usableFromInline internal let session: UnsafePointer<DogmaEngine.Session>
        @usableFromInline internal let hullID: HullID

        @inlinable
        @_lifetime(borrow hull)
        init(hull: borrowing Hull) {
            self.session = hull.session
            self.hullID = hull.id
        }

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
    }
}
