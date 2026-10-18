//
//  Fit.swift
//  DogmaKit
//
//  Created by Artem Shimanski on 18.06.2026.
//

import BitField

public struct Fit: ~Copyable, ~Escapable {
    @usableFromInline internal let session: UnsafeMutablePointer<DogmaEngine.Session>
    
    @inlinable
    @_lifetime(borrow session)
    init(session: UnsafeMutablePointer<DogmaEngine.Session>) {
        self.session = session
    }
    
    /// The fit's pilots. Create with `fit.pilots.add(skillLevel:)`.
    public var pilots: Pilots {
        @_lifetime(borrow self) get {
            Pilots(fit: self)
        }
    }

    /// The simulation environment (beacons, weather, storms); applies to every ship in the
    /// session. Add effects with `fit.environment.add(_:)`.
    public var environment: Environment {
        @_lifetime(borrow self) get {
            Environment(fit: self)
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
