//
//  Fit+Skill.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 31.07.2026.
//

extension Fit {
    public struct Skill: ~Copyable, ~Escapable {
        @usableFromInline internal let session: UnsafeMutablePointer<DogmaEngine.Session>
        public let id: SkillID
        @inlinable var entityID: EntityID {id.rawValue}
        
        @inlinable
        @_lifetime(borrow session)
        init(session: UnsafeMutablePointer<DogmaEngine.Session>, id: SkillID) {
            self.session = session
            self.id = id
        }
        
        @inlinable
        var entity: Entity {
            get {
                session.pointee.entities[entityID]!
            }
            nonmutating set {
                session.pointee.entities[entityID] = newValue
            }
        }
        @inlinable public var typeID: TypeID { entity.typeID }
        @inlinable public var groupID: GroupID { entity.groupID }
        @inlinable public var categoryID: CategoryID { entity.categoryID }

        
        @inlinable
        public var level: UInt8 {
            get {
                entity.kind.skillLevel ?? 0
            }
            nonmutating set {
                entity.kind.skillLevel = min(max(newValue, 0), 5)
            }
        }
    }
}

