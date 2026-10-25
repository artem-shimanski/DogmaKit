//
//  FitStats+Implant.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 01.08.2026.
//

extension FitStats {
    /// Read-only view of an implant. Implants have no derived stats, only attributes and a slot.
    @Snapshottable
    public struct Implant: ~Escapable {
        @usableFromInline internal let session: UnsafePointer<DogmaEngine.Session>
        public let id: ImplantID
        @inlinable var entityID: EntityID {id.rawValue}
        @SnapshotIgnored public let attributes: EntityAttributes

        @inlinable
        @_lifetime(borrow session)
        init(session: UnsafePointer<DogmaEngine.Session>, id: ImplantID) {
            self.session = session
            self.id = id
            self.attributes = EntityAttributes(session: session, entityID: id.rawValue)
        }

        @inlinable
        var entity: Entity {
            session.pointee.entities[entityID]!
        }

        @inlinable public var typeID: TypeID { entity.typeID }
        @inlinable public var groupID: GroupID { entity.groupID }
        @inlinable public var categoryID: CategoryID { entity.categoryID }

        /// Implant slot (`implantness`, 1…10).
        @inlinable
        public var slot: UInt16 {
            entity.kind.implantSlot ?? 0
        }
    }
}
