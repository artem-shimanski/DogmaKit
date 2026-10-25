//
//  FitStats.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 05.07.2026.
//

@Snapshottable
public struct FitStats: ~Escapable {
    @usableFromInline internal let session: UnsafePointer<DogmaEngine.Session>

    @inlinable
    @_lifetime(borrow session)
    init(session: UnsafePointer<DogmaEngine.Session>) {
        self.session = session
    }
    
    @SnapshotNested
    public var pilots: Pilots {
        @_lifetime(borrow self) get {
            Pilots(stats: self)
        }
    }

    /// The simulation environment (beacons, weather, storms).
    @SnapshotNested
    public var environment: Environment {
        @_lifetime(borrow self) get {
            Environment(stats: self)
        }
    }

    // MARK: - Direct access by ID

    @inlinable
    public subscript(id: PilotID) -> Pilot {
        @_lifetime(borrow self) get {
            Pilot(session: session, id: id)
        }
    }

    @inlinable
    public subscript(id: HullID) -> Hull {
        @_lifetime(borrow self) get {
            Hull(session: session, id: id)
        }
    }

    @inlinable
    public subscript(id: ModuleID) -> Module {
        @_lifetime(borrow self) get {
            Module(session: session, id: id)
        }
    }

    @inlinable
    public subscript(id: DroneID) -> Drone {
        @_lifetime(borrow self) get {
            Drone(session: session, id: id)
        }
    }

    @inlinable
    public subscript(id: ChargeID) -> Charge {
        @_lifetime(borrow self) get {
            Charge(session: session, id: id)
        }
    }

    @inlinable
    public subscript(id: SkillID) -> Skill {
        @_lifetime(borrow self) get {
            Skill(session: session, id: id)
        }
    }

    @inlinable
    public subscript(id: ImplantID) -> Implant {
        @_lifetime(borrow self) get {
            Implant(session: session, id: id)
        }
    }

    @inlinable
    public subscript(id: BoosterID) -> Booster {
        @_lifetime(borrow self) get {
            Booster(session: session, id: id)
        }
    }

    @inlinable
    public subscript(id: EnvironmentID) -> EnvironmentEffect {
        @_lifetime(borrow self) get {
            EnvironmentEffect(session: session, id: id)
        }
    }
}

public struct EntityAttributes: ~Escapable {
    public struct SDEDefaultMarker: Sendable {
        @inlinable
        public init() {}
        
        @inlinable
        public static var sde: SDEDefaultMarker { SDEDefaultMarker() }
    }
    
    @usableFromInline var session: UnsafePointer<DogmaEngine.Session>
    @usableFromInline var entityID: EntityID
    
    @inlinable
    public subscript(key: AttributeID) -> Double? {
        session.pointee.context.attributes[AttributeKey(entityID: entityID, attributeID: key)]
    }
    
    @inlinable
    public subscript(key: AttributeID, default defaultValue: SDEDefaultMarker) -> Double {
        if let value = self[key] {
            return value
        }
        else {
            let sde = session.pointee.sde
            return Double(sde[key]?.defaultValue ?? 0)
        }
    }

    @inlinable
    @_lifetime(borrow session)
    init(session: UnsafePointer<DogmaEngine.Session>, entityID: EntityID) {
        self.session = session
        self.entityID = entityID
    }
}
