//
//  Fit+Booster.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 01.08.2026.
//

extension Fit {
    public struct Booster: ~Copyable, ~Escapable {
        @usableFromInline internal let session: UnsafeMutablePointer<DogmaEngine.Session>
        public let id: BoosterID
        @inlinable var entityID: EntityID {id.rawValue}
        
        @inlinable
        @_lifetime(borrow session)
        init(session: UnsafeMutablePointer<DogmaEngine.Session>, id: BoosterID) {
            self.session = session
            self.id = id
        }
        
        @inlinable var entity: Entity { session.pointee.entities[entityID]! }
        @inlinable public var typeID: TypeID { entity.typeID }
        @inlinable public var groupID: GroupID { entity.groupID }
        @inlinable public var categoryID: CategoryID { entity.categoryID }

        @inlinable
        public var slot: UInt16 {
            entity.kind.boosterSlot ?? 0
        }
        
        consuming public func remove() {
            session.pointee.entities.remove(entityID)
        }
        
        
    }
}

