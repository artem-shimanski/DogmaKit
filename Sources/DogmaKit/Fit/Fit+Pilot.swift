//
//  Fit+Pilot.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 16.06.2026.
//

#if os(WASI)
import FoundationEssentials
#else
import Foundation
#endif

extension Fit {
    
    public struct Pilot: ~Copyable, ~Escapable {
        @usableFromInline internal let session: UnsafeMutablePointer<DogmaEngine.Session>
        
        public let id: PilotID
        @inlinable var entityID: EntityID {id.rawValue}

        @inlinable
        @_lifetime(borrow session)
        init(session: UnsafeMutablePointer<DogmaEngine.Session>, id: PilotID) {
            self.session = session
            self.id = id
        }

        
        consuming public func remove() {
            session.pointee.entities.removeAll(in: entityID)
        }
        
        public var hull: Hull {
            @_lifetime(borrow self)
            get {
                Hull(session: session, id: id.hull)
            }
        }
        
        public var skills: Skills {
            @_lifetime(borrow self)
            get {
                Skills(pilot: self)
            }
        }
        
        public var implants: Implants {
            @_lifetime(borrow self)
            get {
                Implants(pilot: self)
            }
        }

        public var boosters: Boosters {
            @_lifetime(borrow self)
            get {
                Boosters(pilot: self)
            }
        }
    }
}
