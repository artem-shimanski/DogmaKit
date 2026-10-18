//
//  Fit+EnvironmentEffect.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 02.08.2026.
//

extension Fit {
    /// One environment effect. It has no state, target or charge; only its type and removal.
    public struct EnvironmentEffect: ~Copyable, ~Escapable {
        @usableFromInline internal let session: UnsafeMutablePointer<DogmaEngine.Session>
        public let id: EnvironmentID
        @inlinable var entityID: EntityID { id.rawValue }

        @inlinable
        @_lifetime(borrow session)
        init(session: UnsafeMutablePointer<DogmaEngine.Session>, id: EnvironmentID) {
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
