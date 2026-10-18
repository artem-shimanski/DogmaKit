//
//  Fit+Charge.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 16.06.2026.
//

import BitField

extension Fit {
    
    public struct Charge: ~Copyable, ~Escapable {
        @usableFromInline internal let session: UnsafeMutablePointer<DogmaEngine.Session>
        public let id: ChargeID
        @inlinable var entityID: EntityID {id.rawValue}

        @inlinable
        @_lifetime(borrow session)
        init(session: UnsafeMutablePointer<DogmaEngine.Session>, id: ChargeID) {
            self.session = session
            self.id = id
        }

        @inlinable var entity: Entity { session.pointee.entities[entityID]! }
        @inlinable public var typeID: TypeID { entity.typeID }
        @inlinable public var groupID: GroupID { entity.groupID }
        @inlinable public var categoryID: CategoryID { entity.categoryID }

        consuming public func remove() {
            session.pointee.entities.remove(entityID)
        }
    }
}
