//
//  Fit+Hull.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 01.07.2026.
//

extension Fit {
    
    public struct Hull: ~Copyable, ~Escapable {
        @usableFromInline internal let session: UnsafeMutablePointer<DogmaEngine.Session>

        public let id: HullID
        @inlinable var entityID: EntityID {id.rawValue}

        @inlinable
        @_lifetime(borrow session)
        init(session: UnsafeMutablePointer<DogmaEngine.Session>, id: HullID) {
            self.session = session
            self.id = id
        }

        @inlinable var entity: Entity { session.pointee.entities[entityID]! }
        @inlinable public var typeID: TypeID { entity.typeID }
        @inlinable public var groupID: GroupID { entity.groupID }
        @inlinable public var categoryID: CategoryID { entity.categoryID }


        public func set(typeID: TypeID) throws(DogmaError) {
            let sde = session.pointee.sde
            guard let info = sde[typeID] else { throw DogmaError.typeNotFound(typeID)}
            let categoryID = info.categoryID.load()
            guard categoryID == .ship || categoryID == .structure else { throw DogmaError.invalidCategory(info.categoryID.load(), expected: [.ship, .structure]) }
            
            let entity = Entity(id: entityID,
                                typeID: typeID,
                                groupID: info.groupID.load(),
                                categoryID: info.categoryID.load(),
                                info: info.reference,
                                kind: categoryID == .ship ? .ship : .station)
            session.pointee.entities[entityID] = entity
        }
        
        public var modules: Modules {
            @_lifetime(borrow self) get {
                Modules(hull: self)
            }
        }

        public var drones: Drones {
            @_lifetime(borrow self) get {
                Drones(hull: self)
            }
        }
    }
}
