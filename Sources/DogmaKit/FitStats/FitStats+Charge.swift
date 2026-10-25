//
//  FitStats+Charge.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 07.07.2026.
//

extension FitStats {
    @Snapshottable
    public struct Charge: ~Escapable {
        @usableFromInline internal let session: UnsafePointer<DogmaEngine.Session>
        public let id: ChargeID
        @inlinable var entityID: EntityID {id.rawValue}
        @SnapshotIgnored public let attributes: EntityAttributes
        
        @inlinable
        @_lifetime(borrow session)
        init(session: UnsafePointer<DogmaEngine.Session>, id: ChargeID) {
            self.session = session
            self.id = id
            self.attributes = EntityAttributes(session: session, entityID: id.rawValue)
        }

        @inlinable
        var entity: Entity {
            session.pointee.entities[entityID]!
        }

        @inlinable public var typeID: TypeID { entity.typeID }
    }
}
